defmodule Ulam.UlamAST do
  defmodule Meta do
    defstruct line: nil,
              contains: [],
              dependencies: []

    def from_elixir(elixir_meta) do
      %Meta{line: Keyword.get(elixir_meta, :line)}
    end
  end

  defmodule LitInteger do
    defstruct value: nil,
              meta: %Meta{}
  end

  defmodule LitReal do
    defstruct value: nil,
              meta: %Meta{}
  end

  defmodule TypeVector do
    defstruct size: nil,
              lower: nil,
              upper: nil,
              missing_data: false,
              meta: %Meta{}
  end

  defmodule TypeArray do
    defstruct size: nil,
              element_type: nil,
              missing_data: false,
              meta: %Meta{}
  end

  defmodule TypeInteger do
    defstruct lower: nil,
              upper: nil,
              meta: %Meta{}
  end

  defmodule TypeReal do
    defstruct lower: nil,
              upper: nil,
              meta: %Meta{}
  end

  defmodule VariableDeclaration do
    defstruct variable: nil,
              type: nil,
              meta: %Meta{}
  end

  defmodule Variable do
    defstruct name: nil,
              meta: %Meta{}
  end

  defmodule If do
    defstruct condition: nil,
              then: [],
              otherwise: [],
              meta: %Meta{}
  end

  defmodule ForLoopRange do
    defstruct variable: nil,
              lower: nil,
              upper: nil,
              meta: %Meta{}
  end

  defmodule ForLoop do
    defstruct ranges: [],
              body: [],
              meta: %Meta{}
  end

  defmodule IndexedExpression do
    defstruct expression: nil,
              indices: [],
              meta: %Meta{}
  end

  defmodule Sample do
    defstruct left: nil,
              right: nil,
              meta: %Meta{}
  end

  defmodule Assign do
    defstruct left: nil,
              right: nil,
              meta: %Meta{}
  end

  defmodule BinOp do
    defstruct operator: nil,
              left: nil,
              right: nil,
              meta: %Meta{}
  end

  defmodule UnOp do
    defstruct operator: nil,
              operand: nil,
              meta: %Meta{}
  end

  defmodule FunctionCall do
    defstruct function: nil,
              arguments: [],
              meta: %Meta{}
  end

  @delta_indent 2

  def prewalk_list(ast_nodes, accum, transformer) do
    {reversed_nodes, new_accum} =
      Enum.reduce(ast_nodes, {[], accum}, fn ast_node, {transformed_nodes, current_accum} ->
        {transformed_node, new_accum} = prewalk(ast_node, current_accum, transformer)
        {[transformed_node | transformed_nodes], new_accum}
      end)

    {Enum.reverse(reversed_nodes), new_accum}
  end

  def serialize_statements_to_iolist(ast_nodes, indent_level \\ 0) do
    whitespace = String.duplicate(" ", indent_level)

    lines =
      for ast_node <- ast_nodes do
        [whitespace, serialize(ast_node, indent_level)]
      end

    Enum.intersperse(lines, "\n")
  end

  def serialize_statements_as_iodata(ast_nodes, indent_level \\ 0) do
    whitespace = String.duplicate(" ", indent_level)

    lines =
      for ast_node <- ast_nodes do
        [whitespace, serialize(ast_node, indent_level)]
      end

    Enum.intersperse(lines, "\n")
  end

  def serialize_statements(ast_nodes, indent_level \\ 0) do
    ast_nodes
    |> serialize_statements_as_iodata(indent_level)
    |> IO.iodata_to_binary()
  end

  defp serialize_for_loop([], body, indent_level) do
    _whitespace = String.duplicate(" ", indent_level)
    serialize_statements_to_iolist(body, indent_level)
  end

  defp serialize_for_loop([range | ranges], body, indent_level) do
    whitespace = String.duplicate(" ", indent_level)

    s_var = serialize(range.variable, indent_level)
    s_lower = serialize(range.lower, indent_level)
    s_upper = serialize(range.upper, indent_level)

    """
    for (#{s_var} in #{s_lower}:#{s_upper}) {
    #{serialize_for_loop(ranges, body, indent_level + @delta_indent)}
    #{whitespace}}\
    """
  end

  defp serialize_as_brackets(kv_pairs) do
    inner =
      for {key, value} <- kv_pairs, value != nil do
        [to_string(key), "=", serialize(value)]
      end

    if inner == [] do
      []
    else
      ["<", Enum.intersperse(inner, ", "), ">"]
    end
  end

  defp serialize_simple_type(name, kv_pairs) do
    [name, serialize_as_brackets(kv_pairs)]
  end

  defp serialize_indices(indices) do
    indices
    |> Enum.map(&serialize/1)
    |> Enum.intersperse(", ")
  end

  def serialize_container_type(name, dimensions, kv_pairs) do
    serialized_dimensions = serialize_indices(dimensions)
    serialized_kv_pairs = serialize_as_brackets(kv_pairs)

    "#{name}[#{serialized_dimensions}]#{serialized_kv_pairs}"
  end

  def serialize(ast_node, indent_level \\ 0) do
    case ast_node do
      %LitInteger{value: value} ->
        to_string(value)

      %LitReal{value: value} ->
        to_string(value)

      %TypeVector{} = type_vector ->
        serialize_container_type("vector", [type_vector.size],
          lower: type_vector.lower,
          upper: type_vector.upper
        )

      %TypeArray{} = type_array ->
        [
          serialize_container_type("array", [type_array.size], []),
          " ",
          serialize(type_array.element_type)
        ]

      %TypeReal{} = type_real ->
        serialize_simple_type("real",
          lower: type_real.lower,
          upper: type_real.upper
        )

      %TypeInteger{} = type_integer ->
        serialize_simple_type("int",
          lower: type_integer.lower,
          upper: type_integer.upper
        )

      %VariableDeclaration{} = variable_declaration ->
        s_variable = serialize(variable_declaration.variable)
        s_type = serialize(variable_declaration.type)

        "#{s_type} #{s_variable};"

      %Variable{} = variable ->
        variable.name

      %If{} = if_stmt ->
        whitespace = String.duplicate(" ", indent_level)

        if if_stmt.otherwise do
          """
          if (#{serialize(if_stmt.condition, indent_level)}) {
          #{serialize_statements_to_iolist(if_stmt.then, indent_level + @delta_indent)}
          #{whitespace}} else {
          #{serialize_statements_to_iolist(if_stmt.otherwise, indent_level + @delta_indent)}
          #{whitespace}}\
          """
        else
          """
          if (#{serialize(if_stmt.condition, indent_level)}) {
          #{serialize_statements_to_iolist(if_stmt.then, indent_level + @delta_indent)}
          #{whitespace}}\
          """
        end

      %ForLoop{} = for_loop ->
        serialize_for_loop(for_loop.ranges, for_loop.body, indent_level)

      %ForLoopRange{} = for_loop_range ->
        s_var = serialize(for_loop_range.variable, indent_level)
        s_lower = serialize(for_loop_range.lower, indent_level)
        s_upper = serialize(for_loop_range.upper, indent_level)
        "(#{s_var} in #{s_lower}:#{s_upper})"

      %IndexedExpression{} = indexed_expressions ->
        indices_string =
          indexed_expressions.indices
          |> Enum.map(fn index -> serialize(index, indent_level) end)
          |> Enum.intersperse(", ")

        "#{serialize(indexed_expressions.expression, indent_level)}[#{indices_string}]"

      %BinOp{} = bin_op ->
        s_left = serialize(bin_op.left, indent_level)
        r_right = serialize(bin_op.right, indent_level)

        "(#{s_left} #{bin_op.operator} #{r_right})"

      %UnOp{} = un_op ->
        s_operand = serialize(un_op.operand, indent_level)

        "(#{un_op.operator}#{s_operand})"

      %Sample{} = sample ->
        s_left = serialize(sample.left, indent_level)
        r_right = serialize(sample.right, indent_level)

        "#{s_left} ~ #{r_right};"

      %Assign{} = assign ->
        s_left = serialize(assign.left, indent_level)
        r_right = serialize(assign.right, indent_level)

        "#{s_left} = #{r_right};"

      %FunctionCall{} = call ->
        is_log_density? =
          Enum.any?(["_lpdf", "_lpmf", "_lupdf", "_lupmf"], fn suffix ->
            String.ends_with?(call.function, suffix)
          end)

        if is_log_density? do
          # Use the Stan "special syntax" for log densities
          [arg0 | args] = call.arguments

          s_arg0 = serialize(arg0, indent_level)

          args_string =
            args
            |> Enum.map(fn arg -> serialize(arg, indent_level) end)
            |> Enum.intersperse(", ")

          "#{call.function}(#{s_arg0} | #{args_string})"
        else
          # Use the syntax for normal function calls
          arguments_string =
            call.arguments
            |> Enum.map(fn arg -> serialize(arg, indent_level) end)
            |> Enum.intersperse(", ")

          "#{call.function}(#{arguments_string})"
        end
    end
  end

  def prewalk(ast_node, accum, transformer) do
    case ast_node do
      %LitInteger{} = integer ->
        transformer.(integer, accum)

      %LitReal{} = real ->
        transformer.(real, accum)

      %Variable{} = variable ->
        transformer.(variable, accum)

      %ForLoopRange{} = for_loop_range ->
        {new_variable, accum} = prewalk(for_loop_range.variable, accum, transformer)
        {new_lower, accum} = prewalk(for_loop_range.lower, accum, transformer)
        {new_upper, accum} = prewalk(for_loop_range.upper, accum, transformer)

        new_for_loop = %{
          for_loop_range
          | variable: new_variable,
            lower: new_lower,
            upper: new_upper
        }

        transformer.(new_for_loop, accum)

      %ForLoop{} = for_loop ->
        {new_ranges, accum} = prewalk_list(for_loop.ranges, accum, transformer)
        {new_body, accum} = prewalk_list(for_loop.body, accum, transformer)
        new_for_loop = %{for_loop | ranges: new_ranges, body: new_body}
        transformer.(new_for_loop, accum)

      %If{} = if_stmt ->
        {new_condition, accum} = prewalk(if_stmt.condition, accum, transformer)
        {new_then, accum} = prewalk_list(if_stmt.then, accum, transformer)
        {new_otherwise, accum} = prewalk_list(if_stmt.otherwise, accum, transformer)

        new_if_stmt = %{
          if_stmt
          | condition: new_condition,
            then: new_then,
            otherwise: new_otherwise
        }

        transformer.(new_if_stmt, accum)

      %IndexedExpression{} = indexed_expressions ->
        {new_expression, accum} = prewalk(indexed_expressions.expression, accum, transformer)
        {new_indices, accum} = prewalk_list(indexed_expressions.indices, accum, transformer)

        new_indexed_expressions = %IndexedExpression{
          expression: new_expression,
          indices: new_indices
        }

        transformer.(new_indexed_expressions, accum)

      %BinOp{} = bin_op ->
        {new_left, accum} = prewalk(bin_op.left, accum, transformer)
        {new_right, accum} = prewalk(bin_op.right, accum, transformer)
        new_bin_op = %{bin_op | operator: bin_op.operator, left: new_left, right: new_right}
        transformer.(new_bin_op, accum)

      %UnOp{} = un_op ->
        {new_operand, accum} = prewalk(un_op.operand, accum, transformer)
        new_un_op = %{un_op | operator: un_op.operator, operand: new_operand}
        transformer.(new_un_op, accum)

      %Sample{} = sample ->
        {new_right, accum} = prewalk(sample.right, accum, transformer)
        {new_left, accum} = prewalk(sample.left, accum, transformer)
        new_sample = %{sample | left: new_left, right: new_right}
        transformer.(new_sample, accum)

      %Assign{} = assign ->
        {new_right, accum} = prewalk(assign.right, accum, transformer)
        {new_left, accum} = prewalk(assign.left, accum, transformer)
        new_assign = %{assign | left: new_left, right: new_right}
        transformer.(new_assign, accum)

      %FunctionCall{} = call ->
        {new_args, accum} = prewalk_list(call.arguments, accum, transformer)
        new_call = %{call | function: call.function, arguments: new_args}
        transformer.(new_call, accum)
    end
  end
end

defmodule Ulam.MissingDataContainer do
  alias Ulam.UlamAST, as: A
  alias Ulam.UlamAST
  alias Ulam.UlamAST.{Variable, IndexedExpression, If, Sample}

  defstruct type: nil,
            variable: nil,
            dimensions: nil,
            n_missing: nil,
            n_not_missing: nil,
            n_is_missing: nil,
            is_missing: nil,
            index_for_missing_value: nil,
            index_for_not_missing_value: nil,
            missing: nil,
            not_missing: nil

  def is_missing_variable(variable) do
    %Variable{name: variable.name <> "__is_missing"}
  end

  def missing_variable(variable) do
    %Variable{name: variable.name <> "__missing"}
  end

  def not_missing_variable(variable) do
    %Variable{name: variable.name <> "__not_missing"}
  end

  def index_for_missing_value_variable(variable) do
    %Variable{name: variable.name <> "__missing_value_index"}
  end

  def index_for_not_missing_value_variable(variable) do
    %Variable{name: variable.name <> "__not_missing_value_index"}
  end

  def maybe_replace_by_missing_variable(expression, replacement_indexed_expression) do
    case expression do
      indexed_expressions when indexed_expressions == replacement_indexed_expression ->
        variable = replacement_indexed_expression.expression
        # Replace the missing variable access in an intelligent way.
        # As long as the original index expression is valid, this will also be valid.
        # All "inner indices" are data and not parameters, which means that stan
        # can be smart when optimizing the evaluation of derivatives
        # by separating the variable and constant parts.
        %IndexedExpression{
          expression: missing_variable(variable),
          indices: [
            %IndexedExpression{
              expression: index_for_missing_value_variable(variable),
              indices: indexed_expressions.indices
            }
          ]
        }

      other ->
        other
    end
  end

  def maybe_replace_by_not_missing_variable(expression, replacement_indexed_expression) do
    case expression do
      indexed_expressions when indexed_expressions == replacement_indexed_expression ->
        variable = replacement_indexed_expression.expression

        %IndexedExpression{
          expression: not_missing_variable(variable),
          indices: [
            %IndexedExpression{
              expression: index_for_not_missing_value_variable(variable),
              indices: indexed_expressions.indices
            }
          ]
        }

      other ->
        other
    end
  end

  def collect_possibly_missing_values(ulam_ast, variables_with_missing_data) do
    {_ulam_ast, missing_data_expressions} =
      UlamAST.prewalk(ulam_ast, [], fn ast_node, missing_data_expressions ->
        case ast_node do
          %IndexedExpression{} = indexed_expressions ->
            if indexed_expressions.expression in variables_with_missing_data do
              {indexed_expressions, [indexed_expressions | missing_data_expressions]}
            else
              {indexed_expressions, missing_data_expressions}
            end

          other ->
            {other, missing_data_expressions}
        end
      end)

    missing_data_expressions
  end

  def transform_statement_with_maybe_missing_values(sample, indexed_expressions_to_replace) do
    Enum.reduce(indexed_expressions_to_replace, sample, fn indexed_expression, current_sample ->
      variable = indexed_expression.expression
      # Replace by a missing variable
      {branch_for_value_missing, _accum} =
        UlamAST.prewalk(current_sample, nil, fn node, _accum ->
          {maybe_replace_by_missing_variable(node, indexed_expression), nil}
        end)

      # Replace by a non-missing variable
      {branch_for_value_not_missing, _accum} =
        UlamAST.prewalk(current_sample, nil, fn node, _accum ->
          {maybe_replace_by_not_missing_variable(node, indexed_expression), nil}
        end)

      %If{
        condition: %IndexedExpression{
          expression: is_missing_variable(variable),
          indices: indexed_expression.indices
        },
        then: [branch_for_value_missing],
        otherwise: [branch_for_value_not_missing]
      }
    end)
  end

  def handle_variables_with_missing_data(ast, variables_with_missing_data) do
    indexed_expressions_to_replace =
      collect_possibly_missing_values(ast, variables_with_missing_data)

    {new_ast, _accum} =
      UlamAST.prewalk(ast, nil, fn ast_node, accum ->
        case ast_node do
          %Sample{} = sample ->
            new_ast_node =
              transform_statement_with_maybe_missing_values(
                sample,
                indexed_expressions_to_replace
              )

            {new_ast_node, accum}

          other ->
            {other, accum}
        end
      end)

    new_ast
  end

  def test() do
    x = %A.Variable{name: "x"}
    y = %A.Variable{name: "y"}

    i = %A.Variable{name: "i"}
    j = %A.Variable{name: "j"}
    # k = %Variable{name: "k"}

    error = %A.Variable{name: "error"}
    slope = %A.Variable{name: "slope"}
    intercept = %A.Variable{name: "intercept"}

    stmt1 = %A.Sample{
      left: %A.IndexedExpression{
        expression: y,
        indices: [i, j]
      },
      right: %A.FunctionCall{
        function: "normal",
        arguments: [
          %A.BinOp{
            operator: "+",
            left: %A.BinOp{
              operator: "*",
              left: slope,
              right: %A.IndexedExpression{
                expression: x,
                indices: [i, j]
              }
            },
            right: intercept
          },
          error
        ]
      }
    }

    for_loop = %A.ForLoop{
      ranges: [
        %A.ForLoopRange{
          variable: i,
          lower: %A.LitInteger{value: 1},
          upper: %A.Variable{name: "N"}
        },
        %A.ForLoopRange{
          variable: j,
          lower: %A.LitInteger{value: 1},
          upper: %A.Variable{name: "N"}
        }
      ],
      body: [
        stmt1
      ]
    }

    contents =
      handle_variables_with_missing_data(for_loop, [x, y])
      |> UlamAST.serialize()

    File.write!("example.stan", contents)
  end
end
