defmodule Ulam.UlamModelCompiler.BernoulliModelTest do
  use ExUnit.Case, async: true
  require Ulam.UlamModel, as: UlamModel
  alias Ulam.TestSupport

  setup do
    TestSupport.clean_directories([
      "test/ulam/ulam_model_compiler/bernoulli_model"
    ])
  end

  def cross_platform_assert_equal(left, right) do
    canonical_left = String.replace(left, "\r\n", "\n")
    canonical_right = String.replace(right, "\r\n", "\n")

    assert canonical_left == canonical_right
  end

  @tag slow: true, timeout: :infinity
  test "regression model" do
    stan_file = "test/ulam/ulam_model_compiler/bernoulli_model/bernoulli_model.stan"

    ulam_model =
      UlamModel.new stan_file: stan_file do
        data do
          n :: int(lower: 0)
          y :: array(n, int(lower: 0, upper: 1))
        end

        parameters do
          theta :: real(lower: 0, upper: 1)
        end

        model do
          theta <~> beta(1, 1)
          y <~> bernoulli(theta)
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
