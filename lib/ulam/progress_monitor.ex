defmodule Ulam.ProgressMonitor do
  alias Ulam.Stan.RefreshHandlerState

  @callback start_chain_monitors(list(integer()), integer()) :: any()

  @callback await(list(any())) :: :ok

  @callback clean_up(list(any())) :: :ok

  @callback update_value(%RefreshHandlerState{}, integer()) :: :ok
end
