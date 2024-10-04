defmodule Ulam.UlamModelCompiler do
  @moduledoc false

  alias Ulam.UlamAST
  alias Ulam.UlamAST.Meta
  alias Ulam.UlamModel
  alias Ulam.Stan.StanModel
  require Ulam.KeywordSpec, as: KeywordSpec

  defp model_already_compiled?(stan_file, new_model_iodata) do
    (
      File.exists?(stan_file) and
      File.exists?(Path.rootname(stan_file)) and
      File.exists?(Path.rootname(stan_file) <> ".hpp") and
      File.read!(stan_file) == to_string(new_model_iodata)
    )
  end

  def compile_model(%UlamModel{} = ulam_model) do
    iodata = to_stan_as_iodata(ulam_model)

    stan_model =
      if model_already_compiled?(ulam_model.stan_file, iodata) do
        # Don't recompile the model, that takes a long time!
        StanModel.from_file(ulam_model.stan_file)
      else
        # Compile or recompile the model, it hasn't been compiled yet
        File.write!(ulam_model.stan_file, iodata)
        StanModel.compile_file(ulam_model.stan_file)
      end

    # Return the compiled stan model
    %{ulam_model | stan_model: stan_model, compiled: true}
  end

  def model_from_blocks(stan_file, blocks) do
    %UlamModel{
      functions: get_block(blocks, :functions),
      data: get_block(blocks, :data),
      transformed_data: get_block(blocks, :transformed_data),
      parameters: get_block(blocks, :parameters),
      transformed_parameters: get_block(blocks, :transformed_parameters),
      model: get_block(blocks, :model),
      generated_quantities: get_block(blocks, :generated_quantities),
      stan_file: stan_file
    }
  end

  def model_from_elixir(opts, body, _env) do
    stan_file =
      case Keyword.fetch(opts, :stan_file) do
        {:ok, stan_file} ->
          stan_file

        :error ->
          model_name = Keyword.fetch!(opts, :name)
          Path.join(["ulam_models", model_name, model_name <> ".stan"])
      end

    stan_dir = Path.dirname(stan_file)
    File.mkdir_p!(stan_dir)

    statements = elixir_statements(body)

    blocks =
      for statement <- statements do
        case statement do
          {block_name, _meta, [[do: block_contents]]} ->
            {block_name, block_contents}

          _other ->
            raise %Ulam.UlamModelCompilerError{
              message: "Invalid code in model: #{Macro.to_string(statement)}"
            }
        end
      end

    model_from_blocks(stan_file, blocks)
  end

  def get_block(blocks, block_name) when is_atom(block_name) do
    case Keyword.fetch(blocks, block_name) do
      {:ok, block_body} ->
        from_elixir_statements(block_body)

      :error ->
        nil
    end
  end

  def from_elixir_statements(body) do
    statements = elixir_statements(body)
    Enum.map(statements, &from_elixir_ast/1)
  end

  def handle_maybe_nested_indexed_expression(indexed_expression) do
    {expression, indices} = gather_indices_from_indexed_expression(indexed_expression, [])

    %UlamAST.IndexedExpression{
      expression: expression,
      indices: indices
    }
  end

  def gather_indices_from_indexed_expression(maybe_indexed_expression, indices_so_far) do
    case maybe_indexed_expression do
      # We have at least one index access, for example: x[i], x[i][j], ...
      {{:., _meta1, [Access, :get]}, _meta2, [maybe_inner_indexed_expression, index]} ->
        # Convert the index into something Ulam understands
        ulam_index = from_elixir_ast(index)
        # Keep gathering indices
        gather_indices_from_indexed_expression(
          maybe_inner_indexed_expression,
          [ulam_index | indices_so_far]
        )

      # We have collected all indices, only the indexed variable remains
      other ->
        # Convert the expression into something Ulam understands
        expression = from_elixir_ast(other)
        # Return the expression and all the indices in the correct order
        {expression, indices_so_far}
    end
  end

  def build_for_loop(for_loop) do
    {:for, meta1, arguments} = for_loop

    nr_of_args = length(arguments)
    ranges = Enum.slice(arguments, 0, nr_of_args - 1)
    body = List.last(arguments)

    for_loop_ranges =
      for range <- ranges do
        for_loop_range = from_elixir_ast(range)

        case for_loop_range do
          %UlamAST.ForLoopRange{} ->
            for_loop_range

          other ->
            raise "Invalid range: #{Macro.to_string(other)}"
        end
      end

    body_statements =
      case body do
        [do: something] ->
          Enum.map(elixir_statements(something), &from_elixir_ast/1)

        _other ->
          raise "Invalid for loop:\n#{Macro.to_string(for_loop)}"
      end

    %UlamAST.ForLoop{
      ranges: for_loop_ranges,
      body: body_statements,
      meta: Meta.from_elixir(meta1)
    }
  end

  def from_elixir_ast(ast_node) do
    case ast_node do
      {varname, meta, atom} when is_atom(varname) and is_atom(atom) ->
        %UlamAST.Variable{
          name: to_string(varname),
          meta: UlamAST.Meta.from_elixir(meta)
        }

      integer when is_integer(integer) ->
        %UlamAST.LitInteger{value: integer}

      float when is_float(float) ->
        %UlamAST.LitReal{value: float}

      {{:., _meta1, [Access, :get]}, _meta2, [_x, _i]} = indexed_expression ->
        handle_maybe_nested_indexed_expression(indexed_expression)

      {op, meta, [left, right]} when op in [:+, :-, :*, :/] ->
        %UlamAST.BinOp{
          operator: to_string(op),
          left: from_elixir_ast(left),
          right: from_elixir_ast(right),
          meta: Meta.from_elixir(meta)
        }

      {op, meta, [operand]} when op in [:-] ->
        %UlamAST.UnOp{
          operator: to_string(op),
          operand: from_elixir_ast(operand),
          meta: Meta.from_elixir(meta)
        }

      {:real, meta, [options]} ->
        KeywordSpec.validate!(options, [lower, upper])

        %UlamAST.TypeReal{
          lower: lower && from_elixir_ast(lower),
          upper: upper && from_elixir_ast(upper),
          meta: Meta.from_elixir(meta)
        }

      {:real, meta, []} ->
        %UlamAST.TypeReal{
          lower: nil,
          upper: nil,
          meta: Meta.from_elixir(meta)
        }

      {:int, meta, [options]} ->
        KeywordSpec.validate!(options, [lower, upper])

        %UlamAST.TypeInteger{
          lower: lower && from_elixir_ast(lower),
          upper: upper && from_elixir_ast(upper),
          meta: Meta.from_elixir(meta)
        }

      {:int, meta, []} ->
        %UlamAST.TypeInteger{
          lower: nil,
          upper: nil,
          meta: Meta.from_elixir(meta)
        }

      {:vector, meta, [size, options]} ->
        KeywordSpec.validate!(options, [lower, upper, missing_data])

        %UlamAST.TypeVector{
          size: from_elixir_ast(size),
          lower: lower && from_elixir_ast(lower),
          upper: upper && from_elixir_ast(upper),
          missing_data: missing_data,
          meta: Meta.from_elixir(meta)
        }

      {:vector, meta, [size]} ->
        %UlamAST.TypeVector{
          size: from_elixir_ast(size),
          lower: nil,
          upper: nil,
          missing_data: false,
          meta: Meta.from_elixir(meta)
        }

      {:array, meta, [size, element_type, options]} ->
        KeywordSpec.validate!(options, [missing_data])

        %UlamAST.TypeArray{
          size: from_elixir_ast(size),
          element_type: from_elixir_ast(element_type),
          missing_data: missing_data,
          meta: Meta.from_elixir(meta)
        }

      {:array, meta, [size, element_type]} ->
        %UlamAST.TypeArray{
          size: from_elixir_ast(size),
          element_type: from_elixir_ast(element_type),
          missing_data: false,
          meta: Meta.from_elixir(meta)
        }

      {:<~>, meta, [left, right]} ->
        %UlamAST.Sample{
          left: from_elixir_ast(left),
          right: from_elixir_ast(right),
          meta: Meta.from_elixir(meta)
        }

      {:=, meta, [left, right]} ->
        %UlamAST.Assign{
          left: from_elixir_ast(left),
          right: from_elixir_ast(right),
          meta: Meta.from_elixir(meta)
        }

      {:"::", meta, [left, right]} ->
        %UlamAST.VariableDeclaration{
          variable: from_elixir_ast(left),
          type: from_elixir_ast(right),
          meta: Meta.from_elixir(meta)
        }

      {:if, meta, [condition, [do: then]]} ->
        %UlamAST.If{
          condition: from_elixir_ast(condition),
          then: Enum.map(elixir_statements(then), &from_elixir_ast/1),
          meta: Meta.from_elixir(meta)
        }

      {:if, meta, [condition, [do: then, else: otherwise]]} ->
        %UlamAST.If{
          condition: from_elixir_ast(condition),
          then: Enum.map(elixir_statements(then), &from_elixir_ast/1),
          otherwise: Enum.map(elixir_statements(otherwise), &from_elixir_ast/1),
          meta: Meta.from_elixir(meta)
        }

      {:<-, _meta1, [elixir_var, {:.., _meta, [lower, upper]}]} ->
        variable = from_elixir_ast(elixir_var)

        %UlamAST.ForLoopRange{
          variable: variable,
          lower: from_elixir_ast(lower),
          upper: from_elixir_ast(upper)
        }

      {:for, _meta, _arguments} = for_loop ->
        build_for_loop(for_loop)

      {function, meta, arguments} = _function_call when is_atom(function) ->
        %UlamAST.FunctionCall{
          function: to_string(function),
          arguments: Enum.map(arguments, &from_elixir_ast/1),
          meta: Meta.from_elixir(meta)
        }
    end
  end

  defp elixir_statements({:__block__, _meta, statements}), do: statements
  defp elixir_statements(statement), do: [statement]

  defp block_to_stan(_name, nil), do: []

  defp block_to_stan(name, statements) do
    [
      [
        name,
        " {\n",
        UlamAST.serialize_statements(statements, 2),
        "\n}"
      ]
    ]
  end

  def to_stan(ulam_model) do
    ulam_model
    |> to_stan_as_iodata()
    |> IO.iodata_to_binary()
    |> String.replace("\r\n", "\n")
  end

  def to_stan_as_iodata(ulam_model) do
    serialized_blocks =
      block_to_stan("functions", ulam_model.functions) ++
        block_to_stan("data", ulam_model.data) ++
        block_to_stan("transformed data", ulam_model.transformed_data) ++
        block_to_stan("parameters", ulam_model.parameters) ++
        block_to_stan("transformed parameters", ulam_model.transformed_parameters) ++
        block_to_stan("model", ulam_model.model) ++
        block_to_stan("generated quantities", ulam_model.generated_quantities)

    [Enum.intersperse(serialized_blocks, "\n\n"), "\n"]
  end
end
