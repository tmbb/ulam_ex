defmodule Ulam.ProgressMonitors.KinoProgressMonitor do
  @behaviour Ulam.ProgressMonitor

  @impl true
  def start_chain_monitors(chain_ids, total_samples) do
    progress_bars =
      for chain_id <- chain_ids do
        title = "Chain ##{chain_id}"
        KinoProgressBar.new(title, color: :blue, current: 0)
      end

    Kino.render(Kino.Shorts.grid(progress_bars, columns: 1))

    for progress_bar <- progress_bars do
      {progress_bar, [total_samples: total_samples]}
    end
  end

  @impl true
  def await(_ids) do
    :ok
  end

  @impl true
  def clean_up(_ids) do
    :ok
  end

  @impl true
  def update_value(refresh_handler_state, new_value) do
    {progress_bar, args} = refresh_handler_state.progress_widget
    total_samples = Keyword.fetch!(args, :total_samples)

    percent = floor(round(100 * new_value / total_samples))

    KinoProgressBar.set_current(progress_bar, percent)

    :ok
  end
end
