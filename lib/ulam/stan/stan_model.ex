defmodule Ulam.Stan.StanModel do
  alias Ulam.Config
  require Explorer.DataFrame, as: DataFrame
  alias Explorer.Series

  alias Ulam.Stan.ChainRunnerArgs

  @random_seed 459_188_756
  @stan_random_seed_range 0..(2 ** 32)

  defstruct name: nil,
            executable_path: nil

  def new(opts) do
    struct(__MODULE__, opts)
  end

  def with_cwd(new_cwd, fun) do
    old_cwd = File.cwd!()

    try do
      File.cd!(new_cwd)
      fun.()
    after
      File.cd!(old_cwd)
    end
  end

  def with_tmpdir(fun) do
    suffix = "tmp_#{Enum.random(100_000..999_000)}"
    tmp_dir = Path.join(System.tmp_dir!(), suffix)
    File.mkdir_p!(tmp_dir)

    try do
      fun.(tmp_dir)
    after
      # File.rm!(tmp_dir)
    end
  end

  def compile_file(model_path) do
    cmdstan_dir = Config.cmdstan_directory()
    model_name = Path.basename(model_path)
    make_target = Path.rootname(model_path)
    abs_make_target = Path.absname(make_target)

    with_cwd(cmdstan_dir, fn ->
      {_output, 0} = System.cmd("make", [abs_make_target])
    end)

    %__MODULE__{
      name: model_name,
      executable_path: abs_make_target
    }
  end

  def start_progress_bar(progress_bar_id, chain_id, total_samples) do
    label = ["- Chain ", Owl.Data.tag("##{chain_id}", :cyan)]

    Owl.ProgressBar.start(
      id: progress_bar_id,
      label: label,
      total: total_samples,
      timer: true,
      bar_width_ratio: 0.7,
      filled_symbol: Owl.Data.tag("▮", :red),
      empty_symbol: Owl.Data.tag("-", :light_black),
      absolute_values: true,
      partial_symbols: []
    )
  end

  def sample(model, data, opts \\ []) do
    nr_of_chains = Keyword.get(opts, :nr_of_chains, 4)
    nr_of_samples = Keyword.get(opts, :nr_of_samples, 1000)
    nr_of_warmup_samples = Keyword.get(opts, :nr_of_warmup_samples, 1000)
    refresh_every = Keyword.get(opts, :refresh_every, 50)
    random_seed = Keyword.get(opts, :random_seed, @random_seed)
    show_progress_bars = Keyword.get(opts, :show_progress_bars, true)

    # Seed the Elixir random number.
    # NOTE: this won't affect the Stan random number generator.
    :rand.seed(:exsss, {random_seed, random_seed, random_seed})

    # Get deterministic random seeds from the random seed given.
    random_seeds = Enum.map(1..nr_of_chains, fn _ -> Enum.random(@stan_random_seed_range) end)

    progress_bar_ids =
      Enum.map(1..nr_of_chains, fn _ ->
        if show_progress_bars do
          # Generate an ID
          {:progress_bar, make_ref()}
        else
          # Don't generate an ID
          nil
        end
      end)

    # Despite having generated IDs for the progress bars, only actually show progress bars
    # if the they are meant to be shown.
    if show_progress_bars do
      # Make no distinction between warmup samples and regular samples,
      # because for the user it's not that important
      total_samples = nr_of_warmup_samples + nr_of_samples
      # Start all progress bars
      for {progress_bar_id, chain_id} <- Enum.with_index(progress_bar_ids, 1) do
        start_progress_bar(progress_bar_id, chain_id, total_samples)
      end

      Owl.LiveScreen.await_render()
    end

    chain_sampler_arguments =
      for i <- 0..(nr_of_chains - 1) do
        %{
          random_seed: Enum.at(random_seeds, i),
          progress_bar_id: Enum.at(progress_bar_ids, i),
          chain_id: i + 1
        }
      end

    dataframe =
      with_tmpdir(fn tmp_dir ->
        # Write the data to a JSON file (this is the preferred way to communicate with Stan).
        # All chains will read the data from this file.
        data_filepath = Path.join(tmp_dir, "data.json")
        File.write!(data_filepath, Jason.encode_to_iodata!(data))

        # Create a task for each chain so that we can sample in parallel.
        # We could let stan handle the parallelization of the chain sampling,
        # but that way we would lose some control on how we give feedback to the user.
        # It's better to let the BEAM handle multiple stan processes
        # and gather the results at the end.
        chain_tasks =
          Enum.map(chain_sampler_arguments, fn args ->
            Task.async(fn ->
              random_seed = args.random_seed
              chain_id = args.chain_id

              # Create a process which will refresh the progress bars
              # (or whatever means of giving feedback to users which we might have implemented)
              {:ok, refresh_handler} =
                GenServer.start_link(Ulam.Stan.RefreshHandler, %{
                  chain_id: chain_id,
                  # The refresh handler always needs some (maybe fictitious progress bar IDs)
                  progress_bar_id: args.progress_bar_id,
                  # However, the following value is what tells the refresh handler whether
                  # the (maybe fictitious progress bar should be notified)
                  show_progress_bars: show_progress_bars,
                  # The initial value for the progress bar counter.
                  # The refresh handler will always keep the current value for the progress bar
                  # and dynamically evaluate the step sizes for incrementing that value
                  # each time a message comes from Stan.
                  progress_bar_counter: 0,
                  # The refresh handler will notify this process (i.e. the task)
                  # when the Stan program finishes running
                  owner: self()
                })

              # The output path for the samples generated by Stan
              output_path = Path.join(tmp_dir, "output_#{chain_id}.csv")

              chain_args = %ChainRunnerArgs{
                model_executable: model.executable_path,
                data_file: data_filepath,
                output_path: output_path,
                nr_of_samples: nr_of_samples,
                nr_of_warmup_samples: nr_of_warmup_samples,
                refresh_every: refresh_every,
                random_seed: random_seed,
                chain_id: chain_id
              }

              # Run the chain in a way that notifies the refresh handler
              # each time stan gives some feedback and when the program finishes running.
              run_chain(refresh_handler, chain_args)

              # Force the current process to wait for the chain to finish.
              # This won't block other chains because other chains are run in parallel.
              receive do
                {:finished, :ok} ->
                  dataframe_from_output(output_path, chain_id)
              end
            end)
          end)

        # Stan models can take a very long time to run
        dataframes = Task.await_many(chain_tasks, :infinity)
        DataFrame.concat_rows(dataframes)
      end)

    if show_progress_bars do
      # Stop the previous live screen version so that the bars become "detatched"
      # and Owl won't attempt to render them again.
      Owl.LiveScreen.stop()
    end

    dataframe
  end

  defp dataframe_from_output(output_filename, chain_id) do
    transformed_output_filename = "#{Path.rootname(output_filename)}_transformed.csv"

    File.stream!(output_filename)
    |> Stream.reject(fn line -> String.starts_with?(line, "#") end)
    |> Stream.into(File.stream!(transformed_output_filename))
    |> Stream.run()

    df = DataFrame.from_csv!(transformed_output_filename)
    DataFrame.mutate(df, chain_id__: ^chain_id)
  end

  defp stream_output(port, refresh_handler) do
    receive do
      {^port, {:data, data}} ->
        # Notify the refresh handler...
        GenServer.cast(refresh_handler, {:message, data})
        # ... and continue to stream messages as they come.
        stream_output(port, refresh_handler)

      {^port, {:exit_status, 0}} ->
        # Notify the refresh handler that the stan program has finished successfully.
        GenServer.cast(refresh_handler, {:finished, :ok})

      {^port, {:exit_status, status}} ->
        # Notify the refresh handler that the stan program has finished with an error.
        GenServer.cast(refresh_handler, {:finished, {:error, status}})
    end
  end

  defp run_chain(refresh_handler, chain_args) do
    command_args = [
      "sample",
      "num_samples=#{chain_args.nr_of_samples}",
      "num_warmup=#{chain_args.nr_of_warmup_samples}",
      "data",
      "file=#{chain_args.data_file}",
      "output",
      "file=#{chain_args.output_path}",
      "refresh=#{chain_args.refresh_every}",
      "random",
      "seed=#{chain_args.random_seed}"
    ]

    port =
      Port.open(
        {:spawn_executable, chain_args.model_executable},
        [:stderr_to_stdout, :binary, :exit_status, args: command_args]
      )

    stream_output(port, refresh_handler)
  end
end
