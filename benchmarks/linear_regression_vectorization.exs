defmodule Ulam.Benchmarks.LinearRegressionVectorization do
  require Ulam.UlamModel, as: UlamModel
  alias Statistics.Distributions.Normal

  defmodule Params do
    defstruct mu_x: nil,
              sigma_x: nil,
              slope: nil,
              intercept: nil,
              error: nil
  end

  vectorized_model_file = "benchmarks/linear_regression_vectorization/vectorized.stan"
  non_vectorized_model_file = "benchmarks/linear_regression_vectorization/non_vectorized.stan"

  vectorized_model =
    UlamModel.new stan_file: vectorized_model_file do
      data do
        n :: int(lower: 0)
        x :: vector(n)
        y :: vector(n)
      end

      parameters do
        # Parameters for the linear regression
        intercept :: real()
        slope :: real()
        error :: real(lower: 0)
        # Prior on x
        mu_x :: real()
        sigma_x :: real(lower: 0)
      end

      model do
        x <~> normal(mu_x, sigma_x)
        y <~> normal(x * slope + intercept, error)
      end
    end

  non_vectorized_model =
    UlamModel.new stan_file: non_vectorized_model_file do
      data do
        n :: int(lower: 0)
        x :: vector(n)
        y :: vector(n)
      end

      parameters do
        # Parameters for the linear regression
        intercept :: real()
        slope :: real()
        error :: real(lower: 0)
        # Prior on x
        mu_x :: real()
        sigma_x :: real(lower: 0)
      end

      model do
        for i <- 1..n do
          x[i] <~> normal(mu_x, sigma_x)
          y[i] <~> normal(x[i] * slope + intercept, error)
        end
      end
    end

  @vectorized_model UlamModel.compile(vectorized_model)
  @non_vectorized_model UlamModel.compile(non_vectorized_model)

  def generate_data(%Params{} = params) do
    n = 160
    x = for _i <- 1..n, do: Normal.rand(params.mu_x, params.sigma_x)
    y = for x_i <- x, do: Normal.rand(x_i * params.slope + params.intercept, params.error)

    %{x: x, y: y, n: n}
  end

  def run() do
    params = %Params{
      mu_x: 1.2,
      sigma_x: 0.7,
      slope: 0.7,
      intercept: 2.8,
      error: 0.15
    }

    data = generate_data(params)

    Benchee.run(%{
      "vectorized" => fn ->
        UlamModel.sample(@vectorized_model, data, show_progress_bars: false)
      end,
      "non-vectorized" => fn ->
        UlamModel.sample(@non_vectorized_model, data, show_progress_bars: false)
      end,
    })
  end
end

Ulam.Benchmarks.LinearRegressionVectorization.run()
