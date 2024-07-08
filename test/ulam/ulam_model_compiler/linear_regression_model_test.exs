defmodule Ulam.UlamModelCompiler.LinearRegressionModelTest do
  use ExUnit.Case, async: true
  require Ulam.UlamModel, as: UlamModel
  alias Ulam.TestSupport

  setup do
    TestSupport.clean_directories([
      "test/ulam/ulam_model_compiler/linear_regression_model"
    ])
  end

  def cross_platform_assert_equal(left, right) do
    canonical_left = String.replace(left, "\r\n", "\n")
    canonical_right = String.replace(right, "\r\n", "\n")

    assert canonical_left == canonical_right
  end

  @tag slow: true
  test "regression model" do
    stan_file =
      "test/ulam/ulam_model_compiler/linear_regression_model/linear_regression_model.stan"

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
  end
end
