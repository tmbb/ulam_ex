defmodule Ulam.ProgressMonitors.ConsoleProgressBar do
  @behaviour Ulam.ProgressMonitor

  @impl true
  def start_chain_monitors(chain_ids, total_samples) do
    progress_widget_ids =
      Enum.map(chain_ids, fn _i ->
        {:progress_widget, make_ref()}
      end)

    for {widget_id, chain_id} <- Enum.zip(progress_widget_ids, chain_ids) do
      start_chain_monitor(widget_id, chain_id, total_samples)
    end
  end

  defp start_chain_monitor(widget_id, chain_id, total_samples) do
    label = ["- Chain ", Owl.Data.tag("##{chain_id}", :cyan)]

    pid =
      Owl.ProgressBar.start(
        id: widget_id,
        label: label,
        total: total_samples,
        timer: true,
        bar_width_ratio: 0.7,
        filled_symbol: Owl.Data.tag("▮", :red),
        empty_symbol: Owl.Data.tag("-", :light_black),
        absolute_values: true,
        partial_symbols: []
      )

    {pid, [id: widget_id]}
  end

  @impl true
  def await(_widgets) do
    Owl.LiveScreen.await_render()

    :ok
  end

  @impl true
  def clean_up(_widgets) do
    Owl.LiveScreen.stop()
  end

  @impl true
  def update_value(refresh_handler_state, new_value) do
    {_pid, args} = refresh_handler_state.progress_widget

    progress_bar_id = Keyword.fetch!(args, :id)

    progress_widget_counter = refresh_handler_state.progress_widget_counter
    step = new_value - progress_widget_counter

    Owl.ProgressBar.inc(id: progress_bar_id, step: step)

    :ok
  end
end
