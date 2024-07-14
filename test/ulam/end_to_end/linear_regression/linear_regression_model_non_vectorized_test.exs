defmodule Ulam.EndToEnd.LinearRegressionModelNonVectorizedTest do
  use ExUnit.Case, async: true
  require Ulam.UlamModel, as: UlamModel
  alias Ulam.TestSupport

  alias Statistics.Distributions.Normal

  alias Explorer.DataFrame
  alias Explorer.Series

  @moduletag timeout: :infinity


  defmodule Params do
    defstruct mu_x: nil,
              sigma_x: nil,
              slope: nil,
              intercept: nil,
              error: nil
  end

  @model_dir Path.join([
    "test",
    "ulam",
    "end_to_end",
    "linear_regression",
    "linear_regression_model_non_vectorized"
  ])

  setup do
    TestSupport.clean_directories([
      @model_dir
    ])
  end

  @tag slow: true
  def generate_data(%Params{} = params) do
    n = 160
    x = for _i <- 1..n, do: Normal.rand(params.mu_x, params.sigma_x)
    y = for x_i <- x, do: Normal.rand(x_i * params.slope + params.intercept, params.error)

    %{x: x, y: y, n: n}
  end

  test "regression model - non-vectorized" do
    stan_file = Path.join(@model_dir, "linear_regression_model_non_vectorized.stan")

    ulam_model =
      UlamModel.new stan_file: stan_file do
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

    # The code above generates a ulam model
    assert %UlamModel{} = ulam_model
    # The model is not yet compiled
    assert ulam_model.compiled == false

    compiled_model = UlamModel.compile(ulam_model)
    assert compiled_model.compiled == true

    params = %Params{
      mu_x: 1.2,
      sigma_x: 0.7,
      slope: 0.7,
      intercept: 2.8,
      error: 0.15
    }

    # Simulate fake data according to the generative model
    # (implemented in Elixir, not in Stan)
    simulated_data = generate_data(params)

    # Fit the model to the simulated data
    posterior = UlamModel.sample(compiled_model, simulated_data, show_progress_bars: false)
    assert %DataFrame{} = posterior

    tolerance = 0.2

    # Assert that estimates are within 10% of the true value
    assert_in_delta Series.median(posterior[:mu_x]) / params.mu_x, 1.0, tolerance
    assert_in_delta Series.median(posterior[:sigma_x]) / params.sigma_x, 1.0, tolerance
    assert_in_delta Series.median(posterior[:slope]) / params.slope, 1.0, tolerance
    assert_in_delta Series.median(posterior[:intercept]) / params.intercept, 1.0, tolerance
    assert_in_delta Series.median(posterior[:error]) / params.error, 1.0, tolerance
  end
end
