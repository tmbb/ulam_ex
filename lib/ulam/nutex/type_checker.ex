defmodule Ulam.Nutex.TypeChecker do
  alias Ulam.Nutex.TypeEnv
  alias Ulam.Nutex.Kind

  def read_kind({_var_or_fun, meta, _something}), do: Keyword.get(meta, :kind)
  def read_kind(f) when is_float(f), do: %Kind{level: :const, type: :real}
  def read_kind(i) when is_integer(i), do: %Kind{level: :const, type: :integer}

  def type_check(%TypeEnv{} = env, f) when is_float(f), do: {env, f}
  def type_check(%TypeEnv{} = env, i) when is_integer(i), do: {env, i}

  def type_check(%TypeEnv{} = env, {varname, meta, atom}) when is_atom(atom) do
    case TypeEnv.fetch_variable_kind(env, varname) do
      {:ok, kind} ->
        typed_var = {varname, Keyword.put(meta, :kind, kind), atom}
        {env, typed_var}

      :error ->
        raise "Type error"
    end
  end

  def type_check(%TypeEnv{} = env, {function, meta, args}) when is_list(args) do
    {env, reversed_typed_args} =
      Enum.reduce(args, {env, []}, fn arg, {env, types_so_far} ->
        {env, typed_arg} = type_check(env, arg)
        {env, [typed_arg | types_so_far]}
      end)

    typed_args = Enum.reverse(reversed_typed_args)
    arg_kinds = Enum.map(typed_args, fn ta -> read_kind(ta) end)
    arg_types = Enum.map(arg_kinds, fn kind -> kind.type end)
    arg_levels = Enum.map(arg_kinds, fn kind -> kind.level end)

    function_level = Kind.highest_level(arg_levels)

    case TypeEnv.fetch_function_type(env, function) do
      {:ok, type} ->
        case type do
          {:->, expected_arg_types, expected_result_type} ->
            case length(arg_kinds) == length(args) do
              true ->
                are_all_kinds_the_same? =
                  Enum.zip(arg_types, expected_arg_types)
                  |> Enum.all?(fn {actual, expected} -> actual == expected end)

                case are_all_kinds_the_same? do
                  true ->
                    function_kind = %Kind{level: function_level, type: expected_result_type}
                    typed_ast = {function, Keyword.put(meta, :kind, function_kind), typed_args}
                    {env, typed_ast}

                  false ->
                    raise "Type error 1"
                end

              false ->
                raise "Type error 2"
            end

          _other ->
            raise "Type error 3"
        end

      :error ->
        raise "Type error 4"
    end
  end

  defp spaces(n), do: String.duplicate(" ", n)

  def debug_type_check(env, untyped_ast) do
    {_new_env, typed_ast} = type_check(env, untyped_ast)
    debug(typed_ast)
  end

  def debug(typed_ast) do
    debug2(0, typed_ast) |> IO.iodata_to_binary()
  end

  def debug2(indent, {var, _meta, atom} = ast_node) when is_atom(atom) do
    [spaces(indent), to_string(var), " : ", inspect(read_kind(ast_node))]
  end

  def debug2(indent, {func, _meta, args} = ast_node) when is_list(args) do
    debugged_args =
      Enum.intersperse(
        for arg <- args do
          debug2(indent + 2, arg)
        end,
        "\n"
      )

    [spaces(indent), to_string(func), " : ", inspect(read_kind(ast_node)), "\n", debugged_args]
  end

  def debug2(indent, ast_node) do
    [spaces(indent), inspect(ast_node), " : ", inspect(read_kind(ast_node))]
  end
end
