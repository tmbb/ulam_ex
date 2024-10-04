defmodule Ulam.Demo.InferenceDataPlots.LinearRegression do
  alias Statistics.Distributions.Normal
  require Explorer.DataFrame, as: DataFrame
  alias Explorer.Series
  alias Quartz.Plot2D

  alias Quartz.{Figure, Length}

  # We'll need the UlamModel.new/2 macro to compile our models
  require Ulam.UlamModel, as: UlamModel
  alias Ulam.InferenceData

  @debug false

  # Give an explicit file path so that we can inspect the generated stan code
  linear_regression_model_file =
    Path.join(~w[
      demo models inference_data_plots
      linear_regression linear_regression.stan
    ])

  # Compile Elixir AST into stan code
  linear_regression_model =
    UlamModel.new stan_file: linear_regression_model_file do
      data do
        n :: int(lower: 0)
        x :: vector(n)
        y :: vector(n)
      end

      parameters do
        # Parameters for the linear regression
        intercept :: real()
        slope :: real()
        error :: real(lower: 0)
        # Prior on x
        mu_x :: real()
        sigma_x :: real(lower: 0)
      end

      model do
        x <~> normal(mu_x, sigma_x)
        y <~> normal(x * slope + intercept, error)
      end
    end

  # Store the model into a compile-time module attribute.
  # In addition to the compiled struct, the model depends
  # on artifacts stores in the file system.
  @linear_regression_model UlamModel.compile(linear_regression_model)

  # Generative model to simulate the data
  def generate_data(%{} = params) do
    n = 160
    x = for _i <- 1..n, do: Normal.rand(params.mu_x, params.sigma_x)
    y = for x_i <- x, do: Normal.rand(x_i * params.slope + params.intercept, params.error)

    %{x: x, y: y, n: n}
  end

  def sample_model() do
    params = %{
      mu_x: 1.2,
      sigma_x: 0.7,
      slope: 0.7,
      intercept: 2.8,
      error: 0.15
    }

    # Simulate data
    data = generate_data(params)

    # Run the model in order to get an InferenceData struct with the posterior
    draws = UlamModel.sample(@linear_regression_model, data, show_progress_bars: true)
    DataFrame.to_parquet!(draws, "demo/models/inference_data_plots/linear_regression/linear_regression.parquet")
  end

  def energy_plots() do
    idata = InferenceData.from_parquet!("demo/models/inference_data_plots/linear_regression/linear_regression.parquet")

    figure_histogram =
      Figure.new([width: Length.cm(10), height: Length.cm(10), debug: @debug], fn _fig ->
        InferenceData.draw_energy_plots_for_chains(idata, plot_type: :histogram)
      end)

    figure_kde =
      Figure.new([width: Length.cm(10), height: Length.cm(10), debug: @debug], fn _fig ->
        InferenceData.draw_energy_plots_for_chains(idata, plot_type: :kde)
      end)

    Figure.render_to_png_file!(figure_histogram, "examples/inference_data_plots/energy_plot_histogram.png")
    Figure.render_to_png_file!(figure_kde, "examples/inference_data_plots/energy_plot_kde.png")
  end

  def posterior_plots() do
    idata = InferenceData.from_parquet!("demo/models/inference_data_plots/linear_regression/linear_regression.parquet")

    figure_histogram =
      Figure.new([width: Length.cm(6), height: Length.cm(18), debug: @debug], fn _fig ->
        _plots = InferenceData.draw_posterior_plots(idata, plot_type: :histogram)
      end)

    figure_kde =
      Figure.new([width: Length.cm(6), height: Length.cm(18), debug: @debug], fn _fig ->
        _plots = InferenceData.draw_posterior_plots(idata, plot_type: :kde)
      end)

    Figure.render_to_png_file!(figure_histogram, "examples/inference_data_plots/posterior_plots_histogram.png")
    Figure.render_to_png_file!(figure_kde, "examples/inference_data_plots/posterior_plots_kde.png")
  end

  def posterior_and_trace_plots() do
    idata = InferenceData.from_parquet!("demo/models/inference_data_plots/linear_regression/linear_regression.parquet")

    figure_histogram =
      Figure.new([width: Length.cm(10), height: Length.cm(18), debug: @debug], fn _fig ->
        _plots = InferenceData.draw_posterior_and_trace_plots(idata, plot_type: :histogram)
      end)

    figure_kde =
      Figure.new([width: Length.cm(10), height: Length.cm(18), debug: @debug], fn _fig ->
        _plots = InferenceData.draw_posterior_and_trace_plots(idata, plot_type: :kde)
      end)

    Figure.render_to_png_file!(figure_histogram, "examples/inference_data_plots/posterior_plots_histogram_with_trace_plots.png")
    Figure.render_to_png_file!(figure_kde, "examples/inference_data_plots/posterior_plots_kde_with_trace_plots.png")
    Figure.render_to_svg_file!(figure_kde, "examples/inference_data_plots/posterior_plots_kde_with_trace_plots.svg")
  end

  def posterior_and_rank_plots() do
    idata = InferenceData.from_parquet!("demo/models/inference_data_plots/linear_regression/linear_regression.parquet")

    figure_histogram =
      Figure.new([width: Length.cm(10), height: Length.cm(18)], fn _fig ->
        _plots = InferenceData.draw_posterior_and_rank_plots(idata, plot_type: :histogram)
      end)

    figure_kde =
      Figure.new([width: Length.cm(10), height: Length.cm(18)], fn _fig ->
        _plots = InferenceData.draw_posterior_and_rank_plots(idata, plot_type: :kde)
      end)

    Figure.render_to_png_file!(figure_histogram, "examples/inference_data_plots/posterior_plots_histogram_with_rank_plots.png")
    Figure.render_to_png_file!(figure_kde, "examples/inference_data_plots/posterior_plots_kde_with_rank_plots.png")
  end

  def rank_plots() do
    idata = InferenceData.from_parquet!("demo/models/inference_data_plots/linear_regression/linear_regression.parquet")
    draws = idata.draws

    chain_ranks =
      DataFrame.new(
        chain: draws[:chain__],
        parameter: draws[:sigma_x]
      )
      |> DataFrame.sort_by(asc: parameter)
      |> DataFrame.mutate(rank: Series.row_index(parameter))

    chains = Series.distinct(chain_ranks[:chain]) |> Series.to_list()

    ranks_for_chain =
      for chain <- chains do
        DataFrame.filter(chain_ranks, chain == ^chain)[:rank]
      end

    # bin_width = Plot2D.default_bin_width_for_histogram(chain_ranks[:rank])

    histogram_style = [
      filled: false,
      stroke: :top
    ]

    figure =
      Figure.new([width: Length.cm(6), height: Length.cm(4), debug: @debug], fn _fig ->
        plot = Plot2D.new()
        margin_top = Length.axis_fraction(0.075, axis: Plot2D.get_axis(plot, "y"))

        Enum.reduce(ranks_for_chain, plot, fn ranks, p ->
          Plot2D.draw_histogram(p, ranks, style: histogram_style)
        end)
        |> Plot2D.put_minimum_axis_end_margin("y", margin_top)
        |> Plot2D.finalize()
      end)

    Figure.render_to_png_file!(figure, "examples/inference_data_plots/rank_plot.png")
  end
end
