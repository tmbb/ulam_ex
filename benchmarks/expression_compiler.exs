defmodule Ulam.Benchmarks.Nutex.Math.ExpressionCompiler do
  use Ulam.Nutex.Math.Operators
  alias Ulam.Nutex.Math
  alias Ulam.Nutex.Math.Compiler

  def normal_log_density() do
    i = Math.v("i")
    n = Math.v("N")

    y = Math.data("y")
    x = Math.data("x")

    alpha = Math.param("alpha")
    beta = Math.param("beta")
    epsilon = Math.param("epsilon")

    result = - (y[i] - (beta * x[i] + alpha)) * (y[i] - (beta * x[i] + alpha)) / (epsilon * epsilon) - Math.log(epsilon)

    {cache, expression} = Math.optimize_summation(i, n, result)

    _ = Compiler.to_rust(expression)
  end

  def run() do
    Incendium.run(%{
        "normal_log_density" => fn -> normal_log_density() end
      },
      title: "Expression compiler")
  end
end

Ulam.Benchmarks.Nutex.Math.ExpressionCompiler.run()
