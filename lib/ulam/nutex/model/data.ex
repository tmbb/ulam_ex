defmodule Ulam.Nutex.Model.Data do
  defstruct name: nil,
            rust_name: nil,
            type: nil,
            rust_type: nil

  defp type_to_rust_type({:vector, _length}), do: "Vec<f64>"
  defp type_to_rust_type(:real), do: "f64"
  defp type_to_rust_type(:integer), do: "i32"

  def new(opts) do
    name = Keyword.fetch!(opts, :name)
    type = Keyword.fetch!(opts, :type)
    rust_name = name
    rust_type = type_to_rust_type(type)

    %__MODULE__{
      name: name,
      type: type,
      rust_name: rust_name,
      rust_type: rust_type
    }
  end
end
