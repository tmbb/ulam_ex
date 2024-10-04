defmodule Ulam.InferenceData do
  require Explorer.DataFrame, as: DataFrame
  alias Explorer.Series

  require Quartz.KeywordSpec, as: KeywordSpec
  alias Quartz.Figure
  alias Quartz.Plot2D
  alias Quartz.Length
  alias Quartz.Config
  alias Quartz.Text
  import Quartz.Operators

  @semi_transparent_opacity 0.4

  @derive {Inspect, only: [:draws]}

  defstruct draws: nil,
            variables_order: [],
            variables_display_names: %{},
            units: %{}

  def from_draws(draws) do
    variables_order =
      draws.names
      |> Enum.reject(fn name -> String.ends_with?(name, "__") end)
      |> Enum.sort()

    %__MODULE__{
      draws: draws,
      variables_order: variables_order
    }
  end

  def put_display_name(idata, variable, display_name) do
    %{idata | variables_display_names: Map.put(idata.variables_display_names, variable, display_name)}
  end

  def from_parquet!(path) do
    draws = DataFrame.from_parquet!(path)
    from_draws(draws)
  end

  defp energy_transitions(draws) do
    draws
    |> DataFrame.sort_by(asc: chain__, asc: draw__)
    |> DataFrame.mutate(energy_transition__: window_sum(energy__, 2, weights: [-1.0, 1.0], min_periods: 2))
    |> DataFrame.filter(draw__ != 0)
    |> Access.get(:energy_transition__)
  end

  def estimated_bfmi_for_chain(idata, chain_id) do
    energy = DataFrame.filter(idata.draws, chain__ == ^chain_id)[:energy__]
    energy_transitions = Series.window_sum(energy, 2, weights: [-1.0, 1.0], min_periods: 2)
    energy_deviations = Series.subtract(energy, Series.mean(energy))

    Series.sum(Series.pow(energy_transitions, 2)) / Series.sum(Series.pow(energy_deviations, 2))
  end

  def nr_of_chains(idata) do
    Explorer.Series.n_distinct(idata.draws[:chain__])
  end

  def estimated_bfmi(idata) do
    energy_transitions = energy_transitions(idata.draws)

    energy = idata.draws[:energy__]
    energy_deviations = Series.subtract(energy, Series.mean(energy))

    Series.sum(Series.pow(energy_transitions, 2)) / Series.sum(Series.pow(energy_deviations, 2))
  end

  defp add_bfmi_label_and_adjust_margins(plot, bfmi, opts) do
    KeywordSpec.validate!(opts,
      nr_of_decimal_places: 2,
      text_style: []
    )

    # Make the label text slightly smaller than the tick labels
    normal_text_size = Keyword.get(Config.get_plot_text_attributes([]), :size)
    small_text_size = 0.8 * normal_text_size

    text_style = Keyword.put_new(text_style, :size, small_text_size)

    # Merge the user-given text options with the default options for this figure
    text_opts = Config.get_plot_text_attributes(text_style)
    # Add the prefix for better debugging
    text_opts = [{:prefix, "bfmi_text_label"} | text_opts]

    bfmi_value = :erlang.float_to_binary(bfmi, decimals: nr_of_decimal_places)
    bfmi_label_text = Text.new("BFMI = #{bfmi_value}", text_opts)

    # To make sure the text fits, we'll extend
    # the top and right margins of the plot.

    delta_margin_x = algebra(bfmi_label_text.height * 1.0)
    delta_margin_y = algebra(bfmi_label_text.height * 1.5)

    x_offset = algebra(bfmi_label_text.height * 1.1)
    y_offset = algebra(bfmi_label_text.height * 0.8)

    plot
    |> Plot2D.put_minimum_axis_end_margin("x", delta_margin_x)
    |> Plot2D.put_minimum_axis_end_margin("y", delta_margin_y)
    |> Plot2D.draw_text(bfmi_label_text,
        # Offset from the right of the plot
        x: algebra(Length.axis_fraction(1.0) - x_offset),
        # Offset from the top of the plot
        y: algebra(Length.axis_fraction(0.0) + y_offset),
        x_alignment: :right,
        y_alignment: :top,
        style: text_style
      )
  end

  # def draw_energy_plot(plot, idata) do
  #   energy = idata.draws[:energy__]
  #   energy_deviations = Series.subtract(energy, Series.mean(energy))

  #   energy_transitions = energy_transitions(idata.draws)

  #   plot
  #   |> Plot2D.draw_histogram(energy_deviations, style: [opacity: @semi_transparent_opacity])
  #   |> Plot2D.draw_histogram(energy_transitions, style: [opacity: @semi_transparent_opacity])
  # end

  @default_transitions_label "𝜋E"
  @default_deviations_label "𝜋ΔE"

  def draw_energy_plots_for_chains(idata, opts \\ []) do
    n = nr_of_chains(idata)

    KeywordSpec.validate!(opts, [
      nr_of_columns: 2,
      nr_of_rows: ceil(n / nr_of_columns),
      title_maker: fn idata, chain_id, i -> make_energy_plot_title(idata, chain_id, i) end,
      finalize: true
    ])

    opts =
      opts
      |> Keyword.put_new(:transitions_label, @default_transitions_label)
      |> Keyword.put_new(:deviations_label, @default_deviations_label)

    chains = idata.draws[:chain__] |> Series.distinct() |> Series.to_list()

    nested_bounds =
      Figure.bounds_for_plots_in_grid(
        nr_of_rows: nr_of_rows,
        nr_of_columns: nr_of_columns
      )

    bounds = Enum.concat(nested_bounds)

    non_finalized_plots =
      for {chain_id, i} <- Enum.with_index(chains, 0) do
        plot_bounds = Enum.at(bounds, i)
        title = title_maker.(idata, chain_id, i)

        _plot =
          Plot2D.new()
          |> then(fn p -> if i != 0, do: Plot2D.no_legend(p), else: p end)
          |> draw_energy_plot_for_chain(idata, chain_id, opts)
          |> Plot2D.put_bounds(plot_bounds)
          |> Plot2D.put_title(title)
      end

    if finalize do
      Plot2D.finalize_all(non_finalized_plots)
    end
  end

  def draw_energy_plot_for_chain(plot, idata, chain_id, opts \\ []) do
    KeywordSpec.validate!(opts, [
      deviations_label: @default_deviations_label,
      transitions_label: @default_deviations_label,
      legend_location: :right,
      plot_type: :kde,
      bfmi_label: true,
      opacity: @semi_transparent_opacity
    ])

    draws_for_chain = DataFrame.filter(idata.draws, chain__ == ^chain_id)

    bfmi = estimated_bfmi_for_chain(idata, chain_id)

    energy = draws_for_chain[:energy__]
    energy_deviations = Series.subtract(energy, Series.mean(energy))

    energy_transitions = energy_transitions(draws_for_chain)

    min_value =
      min(
        Series.min(energy_transitions),
        Series.min(energy_deviations)
      )

    max_value =
      max(
        Series.max(energy_transitions),
        Series.max(energy_deviations)
      )

    energy_plotter =
      case plot_type do
        :kde ->
          fn p, values, options ->
            new_options =
              options
              |> Keyword.put(:min, min_value)
              |> Keyword.put(:max, max_value)
              |> Keyword.put(:fill, true)
              |> put_new_in_style(:opacity, opacity)

            Plot2D.draw_kde_plot(p, values, new_options)
          end

        :histogram ->
          fn p, values, options ->
            new_options = put_new_in_style(options, :opacity, opacity)
            Plot2D.draw_histogram(p, values, new_options)
          end
      end

    energy_transitions_opts = Keyword.put(opts, :label, transitions_label)
    energy_deviations_opts = Keyword.put(opts, :label, deviations_label)

    new_plot =
      plot
      |> Plot2D.put_legend_location(legend_location)
      |> energy_plotter.(energy_transitions, energy_transitions_opts)
      |> energy_plotter.(energy_deviations, energy_deviations_opts)
      |> Plot2D.remove_axis_ticks("y")
      |> Plot2D.remove_axis_ticks("x")

    if bfmi_label do
      add_bfmi_label_and_adjust_margins(new_plot, bfmi, opts)
    else
      Plot2D.put_minimum_axis_end_margin(new_plot, "y", Length.pt(6))
    end
  end

  @alphabet ~w[A B C D E F G H I J K L M N O P Q R S T U V W X Y Z]

  def display_name_for(idata, variable) do
    Map.get(idata.variables_display_names, variable, variable)
  end

  def make_posterior_plot_title(idata, variable, nil) do
    "Posterior for #{display_name_for(idata, variable)}"
  end

  def make_posterior_plot_title(idata, variable, i) do
    plot_identifier = Enum.at(@alphabet, i)
    "#{plot_identifier}. Posterior for #{display_name_for(idata, variable)}"
  end

  def numbered_posterior_plot_title_maker(prefix) do
    fn idata, variable, i ->
      "#{prefix}#{i}. Posterior for #{display_name_for(idata, variable)}"
    end
  end

  def make_rank_plot_title(idata, variable, nil) do
    "Rank plot for #{display_name_for(idata, variable)}"
  end

  def make_rank_plot_title(idata, variable, i) do
    plot_identifier = Enum.at(@alphabet, i)
    "#{plot_identifier}. Rank plot for #{display_name_for(idata, variable)}"
  end

  def make_companion_rank_plot_title(idata, variable, _i) do
    "Rank plot for #{display_name_for(idata, variable)}"
  end

  def make_trace_plot_title(idata, variable, i) do
    plot_identifier = Enum.at(@alphabet, i)
    "#{plot_identifier}. Trace plot for #{display_name_for(idata, variable)}"
  end

  def make_companion_trace_plot_title(idata, variable, _i) do
    "Trace plot for #{display_name_for(idata, variable)}"
  end

  def make_energy_plot_title(_idata, chain_id, i) do
    plot_identifier = Enum.at(@alphabet, i)
    "#{plot_identifier}. Energy plot for chain #{chain_id}"
  end

  def put_new_in_style(options, key, value) do
    style = Keyword.get(options, :style, [])
    new_style = Keyword.put_new(style, key, value)
    Keyword.put(options, :style, new_style)
  end

  def draw_posterior_plots(idata, opts \\ []) do
    KeywordSpec.validate!(opts, [
      plot_type: :kde,
      per_chain: true,
      variables: idata.variables_order,
      nr_of_rows: length(variables),
      nr_of_columns: 1,
      title_maker: &make_posterior_plot_title/3,
      finalize: true
    ])

    variables = idata.variables_order
    chains = idata.draws[:chain__] |> Series.distinct() |> Series.to_list()

    nested_bounds =
      Figure.bounds_for_plots_in_grid(
        nr_of_rows: nr_of_rows,
        nr_of_columns: nr_of_columns
      )

    bounds = Enum.concat(nested_bounds)

    posterior_plotter =
      case plot_type do
        :kde ->
          fn p, values, options ->
            Plot2D.draw_kde_plot(p, values, options)
          end

        :histogram ->
          fn p, values, options ->
            new_options = put_new_in_style(options, :opacity, @semi_transparent_opacity)
            Plot2D.draw_histogram(p, values, new_options)
          end
      end

    non_finalized_plots =
      for {variable, i} <- Enum.with_index(variables, 0) do
        plot_bounds = Enum.at(bounds, i)
        title = title_maker.(idata, variable, i)

        plot =
          Plot2D.new()
          |> then(fn p -> Plot2D.no_legend(p) end)
          |> Plot2D.put_bounds(plot_bounds)
          |> Plot2D.remove_axis_ticks("y")
          |> Plot2D.put_axes_margins(Length.cm(0.2))
          |> Plot2D.put_title(title)

        # Are e plotting per chain or aggregating all chains in a single value?
        if per_chain do
          # Draw one element per chain (histogram or line)
          Enum.reduce(chains, plot, fn chain, plot ->
            values = DataFrame.filter(idata.draws, chain__ == ^chain)[variable]
            posterior_plotter.(plot, values, opts)
          end)
        else
          # Draw a single element (histogram or line)
          values = idata.draws[variable]
          posterior_plotter.(plot, values, opts)
        end
      end

    if finalize do
      Plot2D.finalize_all(non_finalized_plots)
    end
  end

  def draw_posterior_plot(plot, idata, variable, opts \\ []) do
    KeywordSpec.validate!(opts, [
      plot_type: :kde,
      per_chain: true,
      title: nil,
      title_maker: &make_posterior_plot_title/3,
      title_alignment: :left,
      index: nil,
      finalize: true
    ])

    plot_title = case title do
      nil ->
        title_maker.(idata, variable, index)

      _other ->
        title
    end

    posterior_plotter =
      case plot_type do
        :kde ->
          fn p, values, options ->
            Plot2D.draw_kde_plot(p, values, options)
          end

        :histogram ->
          fn p, values, options ->
            new_options = put_new_in_style(options, :opacity, @semi_transparent_opacity)
            Plot2D.draw_histogram(p, values, new_options)
          end
      end

    posterior_plot =
      plot
      |> Plot2D.remove_axis_ticks("y")
      |> Plot2D.put_axes_margins(Length.cm(0.2))
      |> Plot2D.put_title(plot_title, alignment: title_alignment)

    posterior_plot =
      # Are we plotting per chain or aggregating all chains in a single value?
      if per_chain do
        chains = Series.distinct(idata.draws[:chain__]) |> Series.to_list()
        # Draw one element per chain (histogram or line)
        Enum.reduce(chains, posterior_plot, fn chain, plot ->
          values = DataFrame.filter(idata.draws, chain__ == ^chain)[variable]
          all_opts = Keyword.put(opts, :label, to_string(chain))
          posterior_plotter.(plot, values, all_opts)
        end)
      else
        # Draw a single element (histogram or line)
        values = idata.draws[variable]
        all_opts = Keyword.put(opts, :label, "All chains")
        posterior_plotter.(posterior_plot, values, all_opts)
      end

    if finalize do
      Plot2D.finalize(posterior_plot)
    else
      posterior_plot
    end
  end

  def draw_rank_plot(plot, idata, variable, opts \\ []) do
    KeywordSpec.validate!(opts, [
      title: nil,
      title_maker: &make_rank_plot_title/3,
      title_alignment: :left,
      index: nil,
      style: [],
      finalize: true
    ])

    plot_title = case title do
      nil ->
        title_maker.(idata, variable, index)

      _other ->
        title
    end

    chain_ranks =
      DataFrame.new(
        chain: idata.draws[:chain__],
        parameter: idata.draws[variable]
      )
      |> DataFrame.sort_by(asc: parameter)
      |> DataFrame.mutate(rank: Series.row_index(^idata.draws[variable]))

    chains = Series.distinct(chain_ranks[:chain]) |> Series.to_list()

    rank_plot =
      Enum.reduce(chains, plot, fn chain, p ->
        ranks = DataFrame.filter(chain_ranks, chain == ^chain)[:rank]
        Plot2D.draw_histogram(p, ranks, style: style)
      end)

    y_axis =  Plot2D.get_axis(rank_plot, "y")
    rank_plot_margin_top = Length.axis_fraction(0.15, axis: y_axis)

    rank_plot =
      rank_plot
      |> Plot2D.put_title(plot_title, alignment: title_alignment)
      |> Plot2D.put_minimum_axis_end_margin("y", rank_plot_margin_top)

    if finalize do
      Plot2D.finalize(rank_plot)
    else
      rank_plot
    end
  end

  def draw_trace_plot(plot, idata, variable, opts \\ []) do
    KeywordSpec.validate!(opts, [
      title: nil,
      title_maker: &make_trace_plot_title/3,
      title_alignment: :left,
      index: nil,
      style: [],
      finalize: true
    ])

    style = Keyword.put_new(style, :stroke_thickness, 0.3)

    plot_title = case title do
      nil ->
        title_maker.(idata, variable, index)

      _other ->
        title
    end

    chains = idata.draws[:chain__] |> Series.distinct() |> Series.to_list()

    margin = Length.axis_fraction(0.075, axis: Plot2D.get_axis(plot, "y"))

    trace_plot =
      Enum.reduce(chains, plot, fn chain, p ->
        y = DataFrame.filter(idata.draws, chain__ == ^chain)[variable]
        x = Series.row_index(y)

        Plot2D.draw_line_plot(p, x, y, style: style)
      end)
      |> Plot2D.put_title(plot_title, alignment: title_alignment)
      |> Plot2D.put_minimum_axis_margins("y", margin)

    if finalize do
      Plot2D.finalize(trace_plot)
    else
      trace_plot
    end
  end

  def draw_posterior_and_rank_plots(idata, opts \\ []) do
    KeywordSpec.validate!(opts, [
      plot_type: :kde,
      per_chain: true,
      variables: idata.variables_order,
      nr_of_rows: length(variables),
      nr_of_columns: 1,
      # Parameters for the posterior plot
      posterior_plot_title_maker: &make_posterior_plot_title/3,
      posterior_plot_style: [],
      posterior_plot_title_alignment: :left,
      # Parameters for the rank plot
      rank_plot_title_maker: &make_companion_rank_plot_title/3,
      rank_plot_style: [],
      rank_plot_title_alignment: :center,
      finalize: true
    ])

    rank_plot_style =
      rank_plot_style
      |> Keyword.put_new(:filled, false)
      |> Keyword.put_new(:stroke, :top)

    nested_bounds =
      Figure.bounds_for_plots_in_grid(
        nr_of_rows: nr_of_rows,
        nr_of_columns: 2 * nr_of_columns
      )

    bound_pairs =
      nested_bounds
      |> Enum.concat()
      |> Enum.chunk_every(2)
      |> Enum.map(&List.to_tuple/1)

    plots =
      for {variable, i} <- Enum.with_index(variables, 0) do
        {posterior_plot_bounds, rank_plot_bounds} = Enum.at(bound_pairs, i)

        posterior_plot =
          Plot2D.new()
          # Only the first plot should have a label
          |> then(fn p -> if i == 0, do: p, else: Plot2D.no_legend(p) end)
          |> Plot2D.put_bounds(posterior_plot_bounds)
          |> draw_posterior_plot(
            idata,
            variable,
            index: i,
            plot_type: plot_type,
            per_chain: per_chain,
            style: posterior_plot_style,
            title_maker: posterior_plot_title_maker,
            title_alignment: posterior_plot_title_alignment,
            finalize: finalize
          )

        rank_plot =
          Plot2D.new()
          |> then(fn p -> Plot2D.no_legend(p) end)
          |> Plot2D.put_bounds(rank_plot_bounds)
          |> draw_rank_plot(
            idata,
            variable,
            index: i,
            style: rank_plot_style,
            title_maker: rank_plot_title_maker,
            title_alignment: rank_plot_title_alignment,
            finalize: finalize
          )

        [posterior_plot, rank_plot]
      end

    plots
  end

  def draw_posterior_and_trace_plots(idata, opts \\ []) do
    KeywordSpec.validate!(opts, [
      plot_type: :kde,
      per_chain: true,
      variables: idata.variables_order,
      nr_of_rows: length(variables),
      nr_of_columns: 1,
      # Parameters for the posterior plot
      posterior_plot_title_maker: &make_posterior_plot_title/3,
      posterior_plot_style: [],
      posterior_plot_title_alignment: :left,
      # Parameters for the rank plot
      trace_plot_title_maker: &make_companion_trace_plot_title/3,
      trace_plot_style: [],
      trace_plot_title_alignment: :center,
      finalize: true
    ])

    trace_plot_style =
      trace_plot_style
      |> Keyword.put_new(:filled, false)
      |> Keyword.put_new(:stroke, :top)

    nested_bounds =
      Figure.bounds_for_plots_in_grid(
        nr_of_rows: nr_of_rows,
        nr_of_columns: 2 * nr_of_columns
      )

    bound_pairs =
      nested_bounds
      |> Enum.concat()
      |> Enum.chunk_every(2)
      |> Enum.map(&List.to_tuple/1)

    plots =
      for {variable, i} <- Enum.with_index(variables, 0) do
        {posterior_plot_bounds, rank_plot_bounds} = Enum.at(bound_pairs, i)

        posterior_plot =
          Plot2D.new()
          |> then(fn p -> if i == 0, do: p, else: Plot2D.no_legend(p) end)
          |> Plot2D.put_bounds(posterior_plot_bounds)
          |> draw_posterior_plot(
            idata,
            variable,
            index: i,
            plot_type: plot_type,
            per_chain: per_chain,
            style: posterior_plot_style,
            title_maker: posterior_plot_title_maker,
            title_alignment: posterior_plot_title_alignment,
            finalize: finalize
          )

        trace_plot =
          Plot2D.new()
          |> then(fn p -> Plot2D.no_legend(p) end)
          |> Plot2D.put_bounds(rank_plot_bounds)
          |> draw_trace_plot(
            idata,
            variable,
            index: i,
            style: trace_plot_style,
            title_maker: trace_plot_title_maker,
            title_alignment: trace_plot_title_alignment,
            finalize: finalize
          )

        [posterior_plot, trace_plot]
      end

    plots
  end
end
