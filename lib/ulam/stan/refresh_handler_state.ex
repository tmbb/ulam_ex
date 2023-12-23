defmodule Ulam.Stan.RefreshHandlerState do
  defstruct chain_id: nil,
            progress_bar_id: nil,
            show_progress_bars: nil,
            progress_bar_counter: 0,
            messages: [],
            owner: nil

  # require Logger

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
