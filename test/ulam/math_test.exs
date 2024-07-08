defmodule Ulam.MathTest do
  use ExUnit.Case, async: true

  alias Ulam.Nutex.Math

  alias Ulam.Nutex.Math.Compiler

  # def gen_variable() do
  #   StreamData.string(:alphanumeric, min_length: 1)
  #   |> StreamData.map(fn name -> %Variable{name: name} end)
  # end

  # def gen_list_and_variable_from_list() do
  #   StreamData.bind(StreamData.list_of(gen_variable(), min_length: 1), fn list ->
  #     StreamData.bind(StreamData.member_of(list), fn elem ->
  #       StreamData.constant({list, elem})
  #     end)
  #   end)
  # end

  # property "a variable depends on itself" do
  #   check all name <- StreamData.string(:printable) do
  #     variable = %Variable{name: name}
  #     assert Algebra.depends_on?(variable, variable)
  #   end
  # end

  test "compile unnormalized normal logp" do
    use Ulam.Nutex.Math.Operators

    i = Math.v("i")
    n = Math.data("n")

    y = Math.data("y")
    x = Math.data("x")

    alpha = Math.param("alpha")
    beta = Math.param("beta")
    epsilon = Math.param("epsilon")

    result =
      -(y[i] - (beta * x[i] + alpha)) * (y[i] - (beta * x[i] + alpha)) / (2.0 * epsilon * epsilon) -
        Math.ln(epsilon)

    {_cache, expression} = Math.optimize_summation(i, n, result)

    Compiler.to_rust(expression)
  end

  test "example 2" do
    use Ulam.Nutex.Math.Operators

    i = Math.v("i")
    n = Math.data("n")

    y = Math.data("y")
    x = Math.data("x")

    result = y[i] - x[i]

    {_cache, _result} = Math.optimize_summation(i, n, result)
  end

  alias Statistics.Distributions.Normal

  def low_precision(float) do
    :erlang.float_to_binary(float, decimals: 3)
  end

  test "demo" do
    mu = 3.4
    sigma = 0.8

    _xs = for _i <- 0..32, do: Normal.rand(mu, sigma)

    # IO.puts("""
    # let data_x = vec![#{xs |> Enum.map(&low_precision/1) |> Enum.intersperse(", ")}];
    # """)
  end
end
