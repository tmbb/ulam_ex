defmodule Ulam.Nutext.ModelTest do
  use ExUnit.Case, async: true

  alias Ulam.Nutex.Math
  alias Ulam.Nutex.Math.Compiler
  alias Ulam.Nutex.Model
  alias Ulam.Nutex.Model.Data
  alias Ulam.Nutex.Model.Parameter

  use Ulam.Nutex.Math.Operators

  def normal_lpdf(y, mu, sigma) do
    -(y - mu) * (y - mu) / (2.0 * sigma * sigma) - Math.ln(sigma)
  end

  test "example 1" do
    i = Math.v("i")
    n = Math.data("n")

    y = Math.data("y")
    x = Math.data("x")

    alpha = Math.param("alpha")
    beta = Math.param("beta")
    epsilon = Math.param("epsilon")

    # result = - (y[i] - (beta * x[i] + alpha)) * (y[i] - (beta * x[i] + alpha)) /
    #             (2.0 * epsilon * epsilon) - Math.ln(epsilon)

    result = normal_lpdf(y[i], beta * x[i] + alpha, epsilon)

    {cache, _expression} = Math.optimize_summation(i, n, result * result)

    model =
      Model.new(
        name: "LinearRegression",
        parameters: [
          Parameter.new(name: "alpha", type: :real),
          Parameter.new(name: "beta", type: :real),
          Parameter.new(name: "epsilon", type: :real)
        ],
        parameter_space_dimensions: 3,
        data: [
          Data.new(name: "x", type: {:vector, {:variable, "N"}}),
          Data.new(name: "y", type: {:vector, {:variable, "N"}}),
          Data.new(name: "n", type: :integer)
        ],
        cache: cache,
        statements: []
      )

    output_path = "../../rust/ulam/src/models/normal_logp_with_cache.rs"

    File.write!(output_path, Model.to_rust(model: model))
  end

  test "model test" do
    quote do
      parameters do
        alpha :: real()
        beta :: real()
        epsilon :: real()
      end

      data do
        n :: integer()
        x :: vector(n)
        y :: vector(n)
      end

      model do
        # The following...
        for i in 0..n do
          y[i] <~> normal(beta * x[i] + alpha, epsilon)
        end

        # is converted into this:
        target <<< sum(i in 0..n, normal_lpdf(y[i], beta * x[i] + alpha, epsilon))

        sum(i in 0..n, normal_lpdf(y[i], sum(j in 0..m, beta[j] * x[j] + alpha[i])), epsilon)

        sum(i in 0..n, normal_lpdf(sum(j in 0..m, y[i][j] * x[j])))

        sum(i in 0..n, sum(j in 0..m, y[i] - x[i][j] * beta[j] - alpha))

        sum(i in 0..n, sum(j in 0..m, y[i] - x[i][j] * beta[j]) - sum(j in 0..m, -alpha))

        sum(i in 0..n, sum(j in 0..m, x[i][j] * beta[j]) + sum(j in 0..m, -alpha))

        sum(
          i in 0..n,
          sum(
            j1 in 0..m,
            sum(j2 in 0..m, (x[i][j1] * beta[i] + alpha) * (x[i][j2] * beta[i] + alpha))
          )
        )
      end
    end
  end
end
