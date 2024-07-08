defmodule Ulam.Algebra.Symbol do
  def to_symbol(name) do
    case name do
      "alpha" -> "𝛼"
      "beta" -> "𝛽"
      "gamma" -> "𝛾"
      "delta" -> "𝛿"
      "epsilon" -> "𝜀"
      "zeta" -> "𝜁"
      "eta" -> "𝜂"
      "theta" -> "𝜃"
      other -> other
    end
  end
end

defmodule Ulam.Algebra do
  defmodule Variable do
    defstruct name: nil

    defimpl Inspect do
      alias Ulam.Algebra.Symbol
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, _opts \\ []) do
        Symbol.to_symbol(expr.name)
      end
    end
  end

  defmodule Sum do
    defstruct terms: []

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, opts \\ []) do
        IAlgebra.container_doc(
          "(",
          expr.terms,
          ")",
          opts,
          fn term, opts -> IAlgebra.to_doc(term, opts) end,
          separator: " +"
        )
      end
    end
  end

  defmodule Prod do
    defstruct terms: []

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, opts \\ []) do
        IAlgebra.container_doc(
          "(",
          expr.terms,
          ")",
          opts,
          fn term, opts -> IAlgebra.to_doc(term, opts) end,
          separator: " ∙"
        )
      end
    end
  end

  defmodule Subscripted do
    defstruct expression: nil,
              subscripts: []

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, opts \\ []) do
        IAlgebra.group(
          IAlgebra.concat([
            IAlgebra.to_doc(expr.expression, opts),
            IAlgebra.container_doc(
              "[",
              expr.subscripts,
              "]",
              opts,
              fn term, opts -> IAlgebra.to_doc(term, opts) end,
              separator: " +"
            )
          ])
        )
      end
    end
  end

  defmodule Summation do
    defstruct summand: nil,
              indices: []

    def size(summation) do
      limits = for {_i, limit} <- summation.indices, do: limit

      case limits do
        [] ->
          0

        [limit] ->
          limit

        multiple_limits ->
          %Ulam.Algebra.Prod{terms: multiple_limits}
      end
    end

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, opts \\ []) do
        IAlgebra.container_doc(
          "(",
          [
            IAlgebra.glue(
              IAlgebra.group(
                IAlgebra.concat([
                  "∑",
                  "_",
                  IAlgebra.container_doc(
                    "{",
                    expr.indices,
                    "}",
                    opts,
                    fn {index, limit}, opts ->
                      IAlgebra.concat([
                        "1 ≤ ",
                        IAlgebra.to_doc(index, opts),
                        " ≤ ",
                        IAlgebra.to_doc(limit, opts)
                      ])
                    end,
                    separator: ","
                  )
                ])
              ),
              " ",
              IAlgebra.to_doc(expr.summand, opts)
            )
          ],
          ")",
          opts,
          fn x, _opts -> x end
        )
      end
    end
  end

  defmodule Function do
    defstruct name: nil,
              arguments: []

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra
      alias Ulam.Algebra.Symbol

      def inspect(function, opts \\ []) do
        IAlgebra.concat([
          Symbol.to_symbol(function.name),
          IAlgebra.container_doc(
            "(",
            function.arguments,
            ")",
            opts,
            fn term, opts -> IAlgebra.to_doc(term, opts) end,
            separator: ","
          )
        ])
      end
    end
  end

  defmodule VectorLength do
    defstruct name: nil,
              arguments: []

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra
      alias Ulam.Algebra.Symbol

      def inspect(function, opts \\ []) do
        IAlgebra.concat([
          Symbol.to_symbol(function.name),
          IAlgebra.container_doc(
            "(",
            function.arguments,
            ")",
            opts,
            fn term, opts -> IAlgebra.to_doc(term, opts) end,
            separator: ","
          )
        ])
      end
    end
  end

  defmodule Power do
    defstruct base: nil,
              exponent: nil

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra

      def inspect(expr, opts \\ []) do
        IAlgebra.concat([
          "(",
          IAlgebra.to_doc(expr.base, opts),
          ")",
          "^",
          "(",
          IAlgebra.to_doc(expr.exponent, opts),
          ")"
        ])
      end
    end
  end

  def example() do
    %Summation{
      summand: %Sum{
        terms: [
          %Variable{name: "beta"},
          %Prod{
            terms: [
              %Variable{name: "zeta"},
              %Prod{
                terms: [
                  %Subscripted{
                    expression: %Variable{name: "x"},
                    subscripts: [
                      %Variable{name: "i"}
                    ]
                  },
                  %Subscripted{
                    expression: %Variable{name: "y"},
                    subscripts: [
                      %Variable{name: "i"}
                    ]
                  }
                ]
              }
            ]
          },
          %Variable{name: "alpha"},
          %Variable{name: "gamma"}
        ]
      },
      indices: [
        {%Variable{name: "i"}, %Variable{name: "N"}}
      ]
    }
  end

  def optimize(expr) do
    case expr do
      %Sum{terms: terms} ->
        %Sum{terms: Enum.map(terms, &optimize/1)}

      %Summation{summand: %Prod{} = _prod} ->
        move_products_out_of_summation(expr)

      %Summation{} ->
        indices = for {i, _} <- expr.indices, do: i

        if not depends_on_any?(expr.summand, indices) do
          %Prod{terms: [Summation.size(expr), expr.summand]}
        else
          case expr.summand do
            %Sum{} = summand ->
              optimized = %Sum{
                terms:
                  for term <- summand.terms do
                    %Summation{summand: term, indices: expr.indices}
                  end
              }

              optimize(optimized)

            _other ->
              expr
          end
        end

      _other ->
        expr
    end
  end

  def apply_rewriting_rules_in_order(all_rules, expression) do
    result =
      Enum.reduce(all_rules, expression, fn rule, current_expression ->
        case rule.(all_rules, current_expression) do
          {:ok, result} ->
            result

          :error ->
            current_expression
        end
      end)

    case result do
      {:ok, transformed} -> transformed
      :error -> expression
    end
  end

  # def split_prod(rules, expr) do
  #   case expr do
  #     %Prod{terms: %Sum{} = sum} ->
  #       sum = traverse_and_apply_rules(sum)

  #       results = %Sum{
  #         terms: for term <- sum.terms do
  #           %Summation{summand: term, indices: expr.indices}
  #         end
  #       }

  #       {:ok, results}

  #     _other ->
  #       :error
  #   end
  # end

  # def split_summation(rules, expr) do
  #   case expr do
  #     %Summation{summand: %Sum{} = sum} ->
  #       sum = traverse_and_apply_rules(sum)

  #       results = %Sum{
  #         terms: for term <- sum.terms do
  #           %Summation{summand: term, indices: expr.indices}
  #         end
  #       }

  #       {:ok, results}

  #     _other ->
  #       :error
  #   end
  # end

  def move_products_out_of_summation(expr) do
    case expr do
      %Summation{summand: %Prod{terms: terms}, indices: indices_with_limits} ->
        indices = Enum.map(indices_with_limits, fn {i, _} -> i end)

        groups =
          Enum.group_by(terms, fn term ->
            depends_on_any?(term, indices)
          end)
          |> Map.put_new(true, [])
          |> Map.put_new(false, [])

        case {groups[true], groups[false]} do
          {[], []} ->
            0

          {_dependents, []} ->
            expr

          {[], independent} ->
            %Prod{terms: independent}

          {dependent, independent} ->
            case dependent do
              [single_term] ->
                %Prod{terms: independent ++ [%{expr | summand: single_term}]}

              multiple_terms ->
                %Prod{terms: independent ++ [%{expr | summand: %Prod{terms: multiple_terms}}]}
            end
        end

      _other ->
        expr
    end
  end

  def move_sums_out_of_summations(expr) do
    case expr do
      %Summation{summand: %Sum{terms: terms}, indices: indices} ->
        groups =
          Enum.group_by(terms, fn term ->
            depends_on_any?(term, indices)
          end)
          |> Map.put_new(true, [])
          |> Map.put_new(false, [])

        result =
          case {groups[true], groups[false]} do
            {[], []} ->
              Summation.size(expr)

            {_dependents, []} ->
              expr

            {[], independent} ->
              %Prod{terms: [Summation.size(expr)] ++ independent}

            {dependent, independent} ->
              %Sum{
                terms: [
                  %Prod{terms: [Summation.size(expr) | independent]},
                  %{expr | terms: dependent}
                ]
              }
          end

        {:ok, result}

      _other ->
        :error
    end
  end

  def depends_on_any?(_expression, []) do
    false
  end

  def depends_on_any?(expression, [variable | variables]) do
    depends_on?(expression, variable) or depends_on_any?(expression, variables)
  end

  def depends_on?(expression, variable) do
    case expression do
      %Variable{} = var ->
        var.name == variable.name

      %Summation{} = summation ->
        variable in summation.indices or
          depends_on?(summation.summand, variable)

      %Function{} = function ->
        Enum.any?(for term <- function.arguments, do: depends_on?(term, variable))

      %Sum{} = sum ->
        Enum.any?(for term <- sum.terms, do: depends_on?(term, variable))

      %Prod{} = prod ->
        Enum.any?(for term <- prod.terms, do: depends_on?(term, variable))

      %Subscripted{} = subs ->
        depends_on?(subs.expression, variable) or
          Enum.any?(for term <- subs.subscripts, do: depends_on?(term, variable))

      %Power{} = power ->
        depends_on?(power.base, variable) or depends_on?(power.exponent, variable)

      _other ->
        false
    end
  end
end
