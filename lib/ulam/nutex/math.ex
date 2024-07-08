defmodule Ulam.Nutex.Math.Inspector do
  def to_superscript(number) do
    characters = to_charlist(number)

    Enum.map(characters, fn char ->
      case char do
        ?0 -> ?⁰
        ?1 -> ?¹
        ?2 -> ?²
        ?3 -> ?³
        ?4 -> ?⁴
        ?5 -> ?⁵
        ?6 -> ?⁶
        ?7 -> ?⁷
        ?8 -> ?⁸
        ?9 -> ?⁹
        other -> other
      end
    end)
    |> to_string()
  end
end

defmodule Ulam.Nutex.Math do
  import Kernel, except: [div: 2]
  alias Ulam.Nutex.Math.Inspector

  alias Ulam.Nutex.Math.ExpressionCache

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

  defmodule Func do
    defstruct name: nil,
              args: [],
              method: false

    defimpl Inspect do
      alias Inspect.Algebra, as: IAlgebra
      alias Ulam.Nutex.Math.Inspector

      def inspect(func, opts \\ []) do
        IAlgebra.concat([
          func.name,
          IAlgebra.container_doc(
            "(",
            func.args,
            ")",
            opts,
            fn arg, opts -> IAlgebra.to_doc(arg, opts) end,
            separator: ","
          )
        ])
      end
    end
  end

  defmodule TypeCast do
    defstruct value: nil,
              type: nil
  end

  defmodule RFrac do
    defstruct num: %{[] => 0},
              den: %{[] => 1}

    def polynomial?(rfrac) do
      map_size(rfrac.den) == 1 and Map.get(rfrac.den, []) != nil
    end

    def proper_polynomial?(rfrac) do
      map_size(rfrac.den) == 1 and Map.get(rfrac.den, []) in [1, 1.0]
    end
  end

  defmodule Subscripted do
    defstruct expression: nil,
              subscripts: []
  end

  defmodule Variable do
    defstruct name: nil,
              kind: nil,
              cache: false

    @behaviour Access

    defimpl Inspect do
      alias Ulam.Algebra.Symbol
      alias Inspect.Algebra, as: IAlgebra

      @impl true
      def inspect(variable, _opts \\ []) do
        Symbol.to_symbol(variable.name)
      end
    end

    def fetch(variable, subscript) do
      result = %Subscripted{
        expression: variable,
        subscripts: [subscript]
      }

      {:ok, result}
    end

    def get_and_update(_variable, _key, _function) do
      raise ArgumentError, "%Variable{} does not implement this function"
    end

    def pop(_variable, _key) do
      raise ArgumentError, "%Variable{} does not implement this function"
    end
  end

  defp zero?(c), do: c == 0 or c == 0.0

  def simplify_rfrac(rfrac) do
    num_no_zeros =
      rfrac.num
      |> Enum.reject(fn {_v, coef} -> zero?(coef) end)
      |> Enum.into(%{})

    den_no_zeros =
      rfrac.den
      |> Enum.reject(fn {_v, coef} -> zero?(coef) end)
      |> Enum.into(%{})

    rfrac = %{rfrac | num: num_no_zeros, den: den_no_zeros}

    num_keys = Map.keys(rfrac.num)

    cond do
      num_keys == [] and Map.keys(rfrac.num) == [] ->
        Map.fetch!(rfrac.den, []) / Map.fetch!(rfrac.den, [])

      Map.get(rfrac.num, []) == 0 ->
        if num_keys == [] do
          0
        else
          %RFrac{num: Map.delete(rfrac.num, [])}
        end

      true ->
        rfrac
    end
  end

  def to_rfrac(%Subscripted{} = subs) do
    %RFrac{num: %{[subs] => 1}}
  end

  def to_rfrac(%Variable{} = var) do
    %RFrac{num: %{[var] => 1}}
  end

  def to_rfrac(%RFrac{} = rfrac) do
    rfrac
  end

  def to_rfrac(number) when is_number(number) do
    %RFrac{num: %{[] => number}}
  end

  def to_rfrac(other) do
    %RFrac{num: %{[other] => 1}}
  end

  def v(name) do
    %Variable{name: name, kind: nil}
  end

  def data(name) do
    %Variable{name: name, kind: :data}
  end

  def param(name) do
    %Variable{name: name, kind: :param}
  end

  functions = [
    :ln,
    :log2,
    :log10,
    :sin,
    :cos,
    :exp,
    :sqrt
  ]

  for func <- functions do
    def unquote(func)(x) do
      %Func{name: unquote(to_string(func)), args: [x], method: true}
    end
  end

  def depends_on_any?(_expression, []) do
    false
  end

  def depends_on_any?(expression, [variable | variables]) do
    depends_on?(expression, variable) or depends_on_any?(expression, variables)
  end

  def treat_as_constant_if_doesnt_depend_on(summation_indices) do
    fn expression ->
      not depends_on_any?(expression, summation_indices)
    end
  end

  def group_variables_in_polynomial_again(poly) do
    new_poly =
      for {factors, coef} <- poly do
        cond do
          is_struct(coef, RFrac) and factors == [] and
            map_size(coef.den) == 1 and Map.get(coef.den, []) != nil ->
            [{[], den_coef}] = Enum.into(coef.den, [])

            for {inner_factors, inner_coef} <- coef.num do
              {inner_factors, inner_coef / den_coef}
            end

          is_struct(coef, RFrac) and map_size(coef.num) == 1 and
            map_size(coef.den) == 1 and Map.get(coef.den, []) != nil ->
            [{num_vars, num_coef}] = Enum.into(coef.num, [])
            [{[], den_coef}] = Enum.into(coef.den, [])

            new_factors = Enum.sort(factors ++ num_vars)
            new_coef = num_coef / den_coef

            {new_factors, new_coef}

          true ->
            {factors, coef}
        end
      end

    new_poly
    |> List.flatten()
    |> Enum.into(%{})
  end

  def group_variables_in_frac_again(rfrac) do
    new_num = group_variables_in_polynomial_again(rfrac.num)
    %{rfrac | num: new_num}
  end

  def optimize_summation(index, limit, expression) do
    optimized1 =
      simplify_rfrac(
        expression,
        treat_as_constant_if_doesnt_depend_on([index])
      )

    cache = %ExpressionCache{}

    {cache, optimized2} = do_optimize_summation(cache, index, limit, optimized1)

    optimized3 = group_variables_in_frac_again(optimized2)

    {cache, optimized3}
  end

  def do_optimize_summation(cache, index, limit, expression) do
    rfrac = to_rfrac(expression)

    if depends_on?(rfrac.den, index) do
      {cache, expression}
    else
      {cache, new_numerator_list} =
        Enum.reduce(rfrac.num, {cache, []}, fn {factors, coef}, {cache, terms} ->
          monomial_depends? =
            factors
            |> Enum.map(fn f -> depends_on?(f, index) end)
            |> Enum.any?()

          if monomial_depends? do
            # Replace the sum by the cache
            expression = %RFrac{num: %{factors => 1}, den: %{[] => 1}}

            {cache, var_name} = ExpressionCache.add_summation(cache, expression, index, limit)

            cache_var = %Variable{name: var_name, kind: :data, cache: true}

            {cache, [{[cache_var], coef} | terms]}
          else
            # The sum is just repeating this N times (where N is the limit)
            {cache, [{factors, mul(coef, %TypeCast{value: limit, type: "f64"})} | terms]}
          end
        end)

      new_numerator = Enum.into(new_numerator_list, %{})

      {cache, %{rfrac | num: new_numerator}}
    end
  end

  def depends_on?(expression, variable) do
    case expression do
      %Variable{} = var ->
        var.name == variable.name

      %Func{} = func ->
        func.args
        |> Enum.map(fn arg -> depends_on?(arg, variable) end)
        |> Enum.any?()

      %RFrac{} = rfrac ->
        num_depends? = monomials_depend_on?(rfrac.num, variable)
        den_depends? = monomials_depend_on?(rfrac.den, variable)

        num_depends? or den_depends?

      %Subscripted{} = subs ->
        expression_depends? = depends_on?(subs.expression, variable)

        subscripts_depends? =
          subs.subscripts
          |> Enum.map(fn index -> depends_on?(index, variable) end)
          |> Enum.any?()

        expression_depends? or subscripts_depends?

      _other ->
        false
    end
  end

  defp monomials_depend_on?(monomials, variable) do
    monomials
    |> Enum.map(fn mon -> monomial_depends_on?(mon, variable) end)
    |> Enum.any?()
  end

  defp monomial_depends_on?({factors, coef}, variable) do
    factors_depend? =
      factors
      |> Enum.map(fn factor -> depends_on?(factor, variable) end)
      |> Enum.any?()

    coef_depends? = depends_on?(coef, variable)

    factors_depend? or coef_depends?
  end

  def subscripted?(expression) do
    case expression do
      %Subscripted{} -> true
      _ -> false
    end
  end

  def product(factors) do
    Enum.reduce(factors, 1, fn next, current_result ->
      mul(next, current_result)
    end)
  end

  defp sum_monomials(terms) do
    Enum.reduce(terms, 0, fn next, current_result ->
      add(next, current_result)
    end)
  end

  defp move_constants_in_monomial({product, coefficient}, treat_as_constant?) do
    constants = Enum.filter(product, treat_as_constant?)
    variables = Enum.reject(product, treat_as_constant?)

    new_coefficient = product(Enum.sort([coefficient | constants]))
    %RFrac{num: %{variables => new_coefficient}}
  end

  def move_constants_in_monomials(monomials, treat_as_constant?) do
    Enum.map(monomials, fn mon -> move_constants_in_monomial(mon, treat_as_constant?) end)
  end

  def simplify_rfrac(rfrac, treat_as_constant?) do
    num = rfrac.num |> move_constants_in_monomials(treat_as_constant?) |> sum_monomials()
    den = rfrac.den |> move_constants_in_monomials(treat_as_constant?) |> sum_monomials()

    div(num, den)
  end

  def add(a, b) when is_number(a) and is_number(b), do: a + b

  def add(a, b) do
    a = to_rfrac(a)
    b = to_rfrac(b)

    result_a_num = multiply_polynomial(a.num, b.den)
    result_b_num = multiply_polynomial(b.num, a.den)

    result_num =
      Map.merge(
        result_a_num,
        result_b_num,
        fn _key, c_a, c_b -> add(c_a, c_b) end
      )

    result_den = multiply_polynomial(a.den, b.den)

    %RFrac{
      num: result_num,
      den: result_den
    }
    |> simplify_rfrac()
  end

  def sub(a, b) when is_number(a) and is_number(b), do: a - b

  def sub(a, b) do
    a = to_rfrac(a)
    b = to_rfrac(b)

    result_a_num = multiply_polynomial(a.num, b.den)

    result_b_num =
      multiply_polynomial(b.num, a.den)
      |> Enum.map(fn {vars, coef} -> {vars, sub(0, coef)} end)
      |> Enum.into(%{})

    result_num =
      Map.merge(
        result_a_num,
        result_b_num,
        fn _key, c_a, c_b -> add(c_a, c_b) end
      )

    result_den = multiply_polynomial(a.den, b.den)

    %RFrac{
      num: result_num,
      den: result_den
    }
    |> simplify_rfrac()
  end

  def mul(a, b) when is_number(a) and is_number(b), do: a * b

  def mul(a, b) do
    a = to_rfrac(a)
    b = to_rfrac(b)

    result_num = multiply_polynomial(a.num, b.num)
    result_den = multiply_polynomial(a.den, b.den)

    %RFrac{num: result_num, den: result_den}
    |> simplify_rfrac()
  end

  def div(a, b) when is_number(a) and is_number(b), do: a / b

  def div(a, b) do
    a = to_rfrac(a)
    b = to_rfrac(b)

    result_num = multiply_polynomial(a.num, b.den)
    result_den = multiply_polynomial(a.den, b.num)

    %RFrac{num: result_num, den: result_den}
    |> simplify_rfrac()
  end

  def multiply_polynomial(p, q) do
    terms =
      for {vars_p, c_p} <- p, {vars_q, c_q} <- q do
        {Enum.sort(vars_p ++ vars_q), mul(c_p, c_q)}
      end

    groups = Enum.group_by(terms, fn {vars, _c} -> vars end, fn {_vars, c} -> c end)

    polynomial =
      for {vars, coefs} <- groups, into: %{} do
        {vars, sum_monomials(coefs)}
      end

    polynomial
  end
end
