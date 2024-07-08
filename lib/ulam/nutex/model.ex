defmodule Ulam.Nutex.Model do
  alias Ulam.Nutex.Math
  alias Ulam.Nutex.Math.ExpressionCache
  alias Ulam.Nutex.Math.Variable
  alias Ulam.Nutex.Math.Compiler
  require EEx

  defstruct name: nil,
            parameters: [],
            parameter_space_dimensions: 0,
            data: [],
            cache: %ExpressionCache{},
            statements: [],
            tape_name: "tape"

  def new(arguments) do
    model = struct(__MODULE__, arguments)
    add_parameter_strides(model)
  end

  def add_parameter_strides(model) do
    parameters = model.parameters

    {new_accumulated_stride, reversed_new_parameters} =
      Enum.reduce(parameters, {0, []}, fn parameter, {accumulated_stride, parameters} ->
        new_accumulated_stride = Math.add(accumulated_stride, parameter.size)
        new_parameter = %{parameter | location: accumulated_stride}
        {new_accumulated_stride, [new_parameter | parameters]}
      end)

    new_parameters = Enum.reverse(reversed_new_parameters)

    new_model = %{
      model
      | parameters: new_parameters,
        parameter_space_dimensions: new_accumulated_stride
    }

    new_model
  end

  defp limit_to_rust(%Variable{} = v), do: v.name
  defp limit_to_rust(other), do: Compiler.to_rust(other)

  defp with_is_last(elements) do
    n = length(elements)

    for {element, index} <- Enum.with_index(elements, 0) do
      {element, index == n - 1}
    end
  end

  EEx.function_from_file(
    :def,
    :logp_template,
    "lib/ulam/nutex/templates/logp.rs",
    [:assigns],
    engine: EEx.SmartEngine
  )

  def to_rust(assigns) do
    logp_template(assigns)
  end
end
