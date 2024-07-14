defmodule Ulam.UlamModelCompiler.LinearRegressionModelVectorizedTest do
  use ExUnit.Case, async: true
  require Ulam.UlamModel, as: UlamModel
  alias Ulam.TestSupport

  @model_dir Path.join([
    "test",
    "ulam",
    "ulam_model_compiler",
    "linear_regression",
    "linear_regression_model_vectorized"
  ])

  setup do
    TestSupport.clean_directories([
      @model_dir
    ])
  end

  test "regression model - vectorized" do
    stan_file = Path.join(@model_dir, "linear_regression_model_vectorized.stan")

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
          x <~> normal(mu_x, sigma_x)
          y <~> normal(x * slope + intercept, error)
        end
      end

    # The code above generates a ulam model
    assert %UlamModel{} = ulam_model
    # The model is not yet compiled
    assert ulam_model.compiled == false

    compiled_model = UlamModel.compile(ulam_model)
    assert compiled_model.compiled == true
  end
end
