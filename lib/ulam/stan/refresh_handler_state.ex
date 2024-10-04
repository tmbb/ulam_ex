defmodule Ulam.Stan.RefreshHandlerState do
  defstruct chain_id: nil,
            progress_widget: nil,
            show_progress_widgets: nil,
            progress_widget_counter: 0,
            messages: [],
            progress_monitor: nil,
            owner: nil

  def append_message(%__MODULE__{} = state, message) do
    %{state | messages: [message | state.messages]}
  end

  def log_messages(%__MODULE__{} = state) do
    messages =
      state.messages
      |> Enum.reverse()
      |> Enum.join()
      |> String.trim()

    IO.puts("")

    messages
    |> Owl.Box.new(title: Owl.Data.tag(" MCMC Chain #{state.chain_id} ", :blue), padding: 1)
    |> Owl.IO.puts()
  end
end
