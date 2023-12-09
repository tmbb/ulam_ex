defmodule Ulam.Stan.RefreshHandler do
  use GenServer

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:message, data}, state) do
    progress_bar_id = state.progress_bar_id
    progress_bar_counter = state.progress_bar_counter

    case maybe_current_value(data) do
      {:ok, new_counter_value} ->
        # We increment the progress bar by steps,
        # so we don't care about the actual value.
        step = new_counter_value - progress_bar_counter

        # Only notify progress bars that actually exist
        if state.show_progress_bars do
          Owl.ProgressBar.inc(id: progress_bar_id, step: step)
        end

        :timer.sleep(160)

        # Even of the progress bar doesn't exist, continue to
        # update the internal state, which is independent of
        # the progress bar itself.
        {:noreply, %{state | progress_bar_counter: new_counter_value}}

      :error ->
        # We have received a message which is not a progress update
        {:noreply, state}
    end
  end

  def handle_cast({:finished, result}, state) do
    # Notify the parent process that the chain sampler has finished
    send(state.owner, {:finished, result})
    {:noreply, state}
  end

  def maybe_current_value(message) do
    # Parse the message sent by the stan program.
    case Regex.run(~r/Iteration:\s+(\d+)\s+\/\s+(\d+)/, message) do
      # Only handle progress updates:
      [_full, current_as_binary, total_as_binary] ->
        {current, ""} = Integer.parse(current_as_binary)
        {_total, ""} = Integer.parse(total_as_binary)
        {:ok, current}

      # Ignore everything else
      _other ->
        :error
    end
  end
end
