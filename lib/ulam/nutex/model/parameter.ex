defmodule Ulam.Nutex.Model.Parameter do
  defstruct name: nil,
            rust_name: nil,
            type: nil,
            rust_type: nil,
            size: 1,
            location: nil

  def type_to_rust_type({:vector, _length}), do: "Vec<f64>"
  def type_to_rust_type(:real), do: "f64"
  def type_to_rust_type(:integer), do: "i32"

  def new(opts) do
    name = Keyword.fetch!(opts, :name)
    type = Keyword.fetch!(opts, :type)

    size =
      case type do
        :real -> 1
        :integer -> 1
        {:vector, length} -> length
      end

    rust_name = name
    rust_type = type_to_rust_type(type)

    %__MODULE__{
      name: name,
      type: type,
      rust_name: rust_name,
      rust_type: rust_type,
      size: size
    }
  end
end
