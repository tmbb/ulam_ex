defmodule Ulam.Stan.RefreshHandler do
  use GenServer
  require Logger
  alias Ulam.Stan.RefreshHandlerState

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:message, data}, %RefreshHandlerState{} = state) do
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

        # Even of the progress bar doesn't exist, continue to
        # update the internal state, which is independent of
        # the progress bar itself.
        {:noreply, %{state | progress_bar_counter: new_counter_value}}

      {:error, message} ->
        new_state = RefreshHandlerState.append_message(state, message)
        # We have received a message which is not a progress update
        {:noreply, new_state}
    end
  end

  def handle_cast({:finished, result}, %RefreshHandlerState{} = state) do
    # Notify the parent process that the chain sampler has finished
    send(state.owner, {:finished, {result, state}})
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
        {:error, message}
    end
  end
end
