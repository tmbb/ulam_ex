defmodule Ulam.Stan.StanProgram do
  defstruct functions: [],
            data: [],
            transformed_data: [],
            parameters: [],
            transformed_parameters: [],
            model: [],
            generated_quantities: []
end
