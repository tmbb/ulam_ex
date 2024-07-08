defmodule Ulam.UlamModelCompilerTest do
  use ExUnit.Case, async: true

  import ExUnitProperties

  alias Ulam.UlamAST
  alias Ulam.UlamModelCompiler

  def gen_valid_stan_variable_name() do
    start_of_varname = StreamData.string([?a..?z, ?_], length: 1)
    rest_of_varname = StreamData.string([?a..?z, ?A..?Z, ?0..?9, ?_])

    StreamData.tuple({start_of_varname, rest_of_varname})
    |> StreamData.map(fn {start, rest} -> start <> rest end)
  end

  def gen_invalid_stan_variable_name() do
    start_of_varname = StreamData.string([?a..?z, ?_], length: 1)
    rest_of_varname = StreamData.string([?a..?z, ?A..?Z, ?0..?9, ?_])
    tail_of_varname = StreamData.string([??, ?!])

    StreamData.tuple({start_of_varname, rest_of_varname, tail_of_varname})
    |> StreamData.map(fn {start, rest, tail} -> start <> rest <> tail end)
  end

  def gen_valid_stan_variable() do
    gen_valid_stan_variable_name()
    |> StreamData.map(fn variable_name -> Macro.var(String.to_atom(variable_name), __MODULE__) end)
  end

  defp to_stan(integer) when is_integer(integer), do: to_string(integer)
  defp to_stan(float) when is_float(float), do: to_string(float)
  defp to_stan(variable), do: Macro.to_string(variable)

  property "literal integers are handled correctly" do
    check all value <- StreamData.integer() do
      assert %UlamAST.LitInteger{
               value: ^value,
               # Literals are not tagged with a line number
               meta: %UlamAST.Meta{line: nil}
             } = UlamModelCompiler.from_elixir_ast(value)
    end
  end

  property "literal floats are handled correctly" do
    check all value <- StreamData.float() do
      assert %UlamAST.LitReal{
               value: ^value,
               # Literals are not tagged with a line number
               meta: %UlamAST.Meta{line: nil}
             } = UlamModelCompiler.from_elixir_ast(value)
    end
  end

  property "literal variables are handled correctly" do
    # NOTE: this test generated dynamic atoms/variables
    # because it compiles code at runtime.
    check all variable_name <- gen_valid_stan_variable_name(),
              line_nr <- StreamData.integer(),
              variable = Code.string_to_quoted!(variable_name, line: line_nr) do
      # Assert that the variable retains the given line number
      assert %UlamAST.Variable{
               name: ^variable_name,
               meta: %UlamAST.Meta{line: ^line_nr}
             } = UlamModelCompiler.from_elixir_ast(variable)
    end
  end

  test "if ... do ... end statement" do
    elixir_ast = Code.string_to_quoted!("if x do y end", line: 1)

    assert UlamModelCompiler.from_elixir_ast(elixir_ast) == %UlamAST.If{
             condition: %UlamAST.Variable{
               name: "x",
               meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
             },
             then: [
               %UlamAST.Variable{
                 name: "y",
                 meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
               }
             ],
             otherwise: [],
             meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
           }
  end

  test "if ... do ... else ... end statement" do
    elixir_ast = Code.string_to_quoted!("if x do y else z end", line: 1)

    assert UlamModelCompiler.from_elixir_ast(elixir_ast) == %UlamAST.If{
             condition: %UlamAST.Variable{
               name: "x",
               meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
             },
             then: [
               %UlamAST.Variable{
                 name: "y",
                 meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
               }
             ],
             otherwise: [
               %UlamAST.Variable{
                 name: "z",
                 meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
               }
             ],
             meta: %UlamAST.Meta{line: 1, contains: [], dependencies: []}
           }
  end

  test "for ... do ... end" do
    for_loop =
      quote do
        for i <- 1..n do
          x <~> y
        end
      end

    ulam_for_loop = UlamModelCompiler.from_elixir_ast(for_loop)

    # Serialize the output (the AST is too complex to check manually)
    assert UlamAST.serialize_as_unix(ulam_for_loop) == """
           for (i in 1:n) {
             x ~ y;
           }\
           """
  end

  test "variable declarations" do
    elixir_declarations =
      quote do
        n :: int(lower: 0)
        x :: vector(n, lower: 0.0, upper: 100.0)
        y :: vector(n, lower: -2.0)
      end

    ulam_statements = UlamModelCompiler.from_elixir_statements(elixir_declarations)

    # Serialize the output (the AST is too complex to check manually)
    assert UlamAST.serialize_statements(ulam_statements) == """
           int<lower=0> n;
           vector[n]<lower=0.0, upper=100.0> x;
           vector[n]<lower=(-2.0)> y;\
           """
  end

  property "indexed expression (1-dimensional)" do
    # Some easily examples that can be checked by hand easily
    e1 = quote(do: x[i])
    u1 = UlamModelCompiler.from_elixir_ast(e1)
    assert UlamAST.serialize(u1) == "x[i]"

    e2 = quote(do: y[12])
    u2 = UlamModelCompiler.from_elixir_ast(e2)
    assert UlamAST.serialize(u2) == "y[12]"

    e3 = quote(do: y[3.14])
    u3 = UlamModelCompiler.from_elixir_ast(e3)
    assert UlamAST.serialize(u3) == "y[3.14]"

    # Random examples generated by StreamData
    check all expression <- gen_valid_stan_variable(),
              index <-
                StreamData.one_of([
                  StreamData.float(),
                  StreamData.integer(),
                  gen_valid_stan_variable()
                ]) do
      elixir_access = quote(do: unquote(expression)[unquote(index)])
      ulam_access = UlamModelCompiler.from_elixir_ast(elixir_access)

      assert ulam_access.expression == UlamModelCompiler.from_elixir_ast(expression)
      assert ulam_access.indices == [UlamModelCompiler.from_elixir_ast(index)]

      assert UlamAST.serialize(ulam_access) == "#{to_stan(expression)}[#{to_stan(index)}]"
    end
  end

  property "indexed expression (2-dimensional)" do
    # Some easily examples that can be checked by hand easily
    e1 = quote(do: x[i][j])
    u1 = UlamModelCompiler.from_elixir_ast(e1)
    assert UlamAST.serialize(u1) == "x[i, j]"

    e2 = quote(do: y[12][45])
    u2 = UlamModelCompiler.from_elixir_ast(e2)
    assert UlamAST.serialize(u2) == "y[12, 45]"

    e3 = quote(do: z[3.14][1.0])
    u3 = UlamModelCompiler.from_elixir_ast(e3)
    assert UlamAST.serialize(u3) == "z[3.14, 1.0]"

    # Keep generators local to the test
    gen_index =
      StreamData.one_of([
        StreamData.float(),
        StreamData.integer(),
        gen_valid_stan_variable()
      ])

    # Random examples generated by StreamData
    check all expression <- gen_valid_stan_variable(),
              index1 <- gen_index,
              index2 <- gen_index do
      elixir_access = quote(do: unquote(expression)[unquote(index1)][unquote(index2)])
      ulam_access = UlamModelCompiler.from_elixir_ast(elixir_access)

      assert ulam_access.expression == UlamModelCompiler.from_elixir_ast(expression)

      assert ulam_access.indices == [
               UlamModelCompiler.from_elixir_ast(index1),
               UlamModelCompiler.from_elixir_ast(index2)
             ]

      assert UlamAST.serialize(ulam_access) == """
             #{to_stan(expression)}[#{to_stan(index1)}, #{to_stan(index2)}]\
             """
    end
  end
end
