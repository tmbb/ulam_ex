defmodule Ulam.Nutex.TypeCheckingTest do
  use ExUnit.Case, async: true

  alias Ulam.Nutex.TypeEnv
  alias Ulam.Nutex.TypeChecker
  alias Ulam.Nutex.Kind

  def sigil_p(binary, _opts),
    do: binary |> String.replace("\r\n", "\n") |> String.trim()

  test "typechecks literal value correctly" do
    env = TypeEnv.from_map(%{})

    assert TypeChecker.debug_type_check(env, 1.2) == "1.2 : const[real]"
    assert TypeChecker.debug_type_check(env, 0.0) == "0.0 : const[real]"
    assert TypeChecker.debug_type_check(env, 3) == "3 : const[integer]"
  end

  test "typechecks variables correctly" do
    env =
      TypeEnv.from_map(%{
        a: %Kind{level: :param, type: :real},
        b: %Kind{level: :data, type: :integer}
      })

    assert TypeChecker.debug_type_check(env, quote(do: a)) == "a : param[real]"
    assert TypeChecker.debug_type_check(env, quote(do: b)) == "b : data[integer]"
  end

  test "typechecks function calls correctly" do
    env = %TypeEnv{
      variables: %{
        a: %Kind{level: :param, type: :real},
        b: %Kind{level: :param, type: :real}
      },
      functions: %{
        +: {:->, [:real, :real], :real}
      }
    }

    assert TypeChecker.debug_type_check(env, quote(do: a + b)) == ~p"""
           + : param[real]
             a : param[real]
             b : param[real]
           """
  end

  test "upgrades levels as required in function calls" do
    env = %TypeEnv{
      variables: %{
        a: %Kind{level: :data, type: :real},
        b: %Kind{level: :param, type: :real}
      },
      functions: %{
        +: {:->, [:real, :real], :real}
      }
    }

    assert TypeChecker.debug_type_check(env, quote(do: a + b)) == ~p"""
           + : param[real]
             a : data[real]
             b : param[real]
           """
  end

  test "nested function calls (1)" do
    env = %TypeEnv{
      variables: %{
        a: %Kind{level: :data, type: :real},
        b: %Kind{level: :param, type: :real},
        c: %Kind{level: :param, type: :real}
      },
      functions: %{
        +: {:->, [:real, :real], :real},
        *: {:->, [:real, :real], :real}
      }
    }

    assert TypeChecker.debug_type_check(env, quote(do: a + b * c)) == ~p"""
           + : param[real]
             a : data[real]
             * : param[real]
               b : param[real]
               c : param[real]
           """
  end

  test "nested function calls (2)" do
    env =
      TypeEnv.default()
      |> TypeEnv.put_variable(:x, Kind.data(:real))
      |> TypeEnv.put_variable(:mu, Kind.param(:real))
      |> TypeEnv.put_variable(:sigma, Kind.param(:real))

    assert TypeChecker.debug_type_check(env, quote(do: normal_lpdf(x, mu, sigma))) == ~p"""
           normal_lpdf : param[real]
             x : data[real]
             mu : param[real]
             sigma : param[real]
           """
  end
end
