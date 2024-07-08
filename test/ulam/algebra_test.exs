defmodule Ulam.AlgebraTest do
  use ExUnit.Case, async: true

  alias Ulam.Algebra

  alias Ulam.Algebra.{
    Variable,
    Sum
  }

  import ExUnitProperties

  def gen_variable() do
    StreamData.string(:alphanumeric, min_length: 1)
    |> StreamData.map(fn name -> %Variable{name: name} end)
  end

  def gen_list_and_variable_from_list() do
    StreamData.bind(StreamData.list_of(gen_variable(), min_length: 1), fn list ->
      StreamData.bind(StreamData.member_of(list), fn elem ->
        StreamData.constant({list, elem})
      end)
    end)
  end

  property "a variable depends on itself" do
    check all name <- StreamData.string(:printable) do
      variable = %Variable{name: name}
      assert Algebra.depends_on?(variable, variable)
    end
  end

  property "a sum depends on a variable" do
    check all {variables, variable} <- gen_list_and_variable_from_list() do
      sum_with_var = %Sum{terms: variables}
      sum_without_var = %Sum{terms: Enum.reject(variables, fn v -> v == variable end)}

      assert Algebra.depends_on?(sum_with_var, variable)
      refute Algebra.depends_on?(sum_without_var, variable)
    end
  end
end
