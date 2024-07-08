defmodule Ulam.Nutex.Kind do
  defstruct level: nil,
            type: nil

  def param(type) do
    %__MODULE__{level: :param, type: type}
  end

  def data(type) do
    %__MODULE__{level: :data, type: type}
  end

  def const(type) do
    %__MODULE__{level: :const, type: type}
  end

  defimpl Inspect do
    alias Inspect.Algebra, as: IAlgebra

    def inspect(kind, _opts) do
      IAlgebra.concat([
        to_string(kind.level),
        "[",
        to_string(kind.type),
        "]"
      ])
    end
  end

  defp level_to_int(:const), do: 0
  defp level_to_int(:data), do: 1
  defp level_to_int(:param), do: 2

  def pick_highest_level(a1, a2) do
    if level_to_int(a1) > level_to_int(a2) do
      a1
    else
      a2
    end
  end

  def highest_level([kind | kinds]) do
    Enum.reduce(kinds, kind, fn next, current ->
      pick_highest_level(next, current)
    end)
  end
end
