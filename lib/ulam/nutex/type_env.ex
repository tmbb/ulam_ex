defmodule Ulam.Nutex.TypeEnv do
  defstruct variables: %{},
            functions: %{}

  def fetch_variable_kind(env, identifier) do
    case Map.fetch(env.variables, identifier) do
      {:ok, type} -> {:ok, type}
      _other -> :error
    end
  end

  def fetch_function_type(env, identifier) do
    case Map.fetch(env.functions, identifier) do
      {:ok, type} -> {:ok, type}
      _other -> :error
    end
  end

  def put_variable(env, identifier, kind) do
    %{env | variables: Map.put(env.variables, identifier, kind)}
  end

  def put_function(env, identifier, type) do
    %{env | functions: Map.put(env.functions, identifier, type)}
  end

  def from_map(variables) do
    %__MODULE__{variables: variables}
  end

  def default() do
    %__MODULE__{
      variables: %{},
      functions: %{
        +: {:->, [:real, :real], :real},
        -: {:->, [:real, :real], :real},
        *: {:->, [:real, :real], :real},
        /: {:->, [:real, :real], :real},
        normal_lpdf: {:->, [:real, :real, :real], :real}
      }
    }
  end
end
