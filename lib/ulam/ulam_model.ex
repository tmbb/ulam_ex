defmodule Ulam.UlamModel do
  @derive {Inspect, only: [:stan_file, :compiled]}

  defstruct functions: [],
            data: [],
            transformed_data: [],
            parameters: [],
            transformed_parameters: [],
            model: [],
            generated_quantities: [],
            stan_file: nil,
            stan_model: nil,
            compiled: false

  alias Ulam.UlamModelCompiler
  alias Ulam.Stan.StanModel

  defmacro new(opts, _ast = [do: body]) do
    quote do
      UlamModelCompiler.model_from_elixir(
        unquote(opts),
        unquote(Macro.escape(body)),
        unquote(Macro.escape(__CALLER__))
      )
    end
  end

  def compile(%__MODULE__{} = ulam_model) do
    UlamModelCompiler.compile_model(ulam_model)
  end

  def sample(%__MODULE__{} = ulam_model, data, opts \\ []) do
    StanModel.sample(ulam_model.stan_model, data, opts)
  end
end
