defmodule Ulam.Algebra do
  defmodule Variable do
    defstruct name: nil
  end

  defmodule Monomial do
    defstruct factors: %{}
  end

  defmodule Polynomial do
    defstruct terms: %{}
  end

  defmodule Subscripted do
    defstruct expression: nil,
              indices: []
  end

  defmodule Summation do
    defstruct summand: nil,
              indices: []
  end

  def simplify_polynomial_terms(terms) do
    for {_value, coef} = term <- terms, coef != 0 and coef != 0.0, into: %{} do
      term
    end
  end

  def simplify_monomial_terms(factors) do
    for {_value, coef} = factor <- factors, coef != 0 and coef != 0.0, into: %{} do
      factor
    end
  end

  def to_polynomial(%Polynomial{} = p), do: p
  def to_polynomial(%Monomial{} = m), do: %Polynomial{terms: %{m => 1}}

  def to_polynomial(other) do
    %Polynomial{
      terms: %{
        %Monomial{
          factors: %{other => 1}
        } => 1
      }
    }
  end

  def to_monomial(%Monomial{} = m), do: m

  def to_monomial(other) do
    %Monomial{
      factors: %{other => 1}
    }
  end

  def add(a, b) do
    poly_a = to_polynomial(a)
    poly_b = to_polynomial(b)

    new_terms = Map.merge(poly_a.terms, poly_b.terms, fn _key, a_i, b_i -> a_i + b_i end)
    %Polynomial{terms: simplify_polynomial_terms(new_terms)}
  end

  def subtract(a, b) do
    poly_a = to_polynomial(a)
    poly_b = to_polynomial(b)

    poly_b = %{poly_b | terms: for({x, c} <- poly_b.terms, into: %{}, do: {x, -c})}

    new_terms = Map.merge(poly_a.terms, poly_b.terms, fn _key, a_i, b_i -> a_i - b_i end)
    %Polynomial{terms: simplify_polynomial_terms(new_terms)}
  end

  def multiply(a, b)
      when (is_struct(a, Monomial) or is_struct(a, Variable) or is_struct(a, Subscripted)) and
             (is_struct(b, Monomial) or is_struct(b, Variable) or is_struct(b, Subscripted)) do
    mon_a = to_monomial(a)
    mon_b = to_monomial(b)

    new_factors = Map.merge(mon_a.factors, mon_b.factors, fn _key, a_i, b_i -> a_i + b_i end)
    %Monomial{factors: simplify_monomial_terms(new_factors)}
  end

  def divide(a, b)
      when (is_struct(a, Monomial) or is_struct(a, Variable) or is_struct(a, Subscripted)) and
             (is_struct(b, Monomial) or is_struct(b, Variable) or is_struct(b, Subscripted)) do
    mon_a = to_monomial(a)
    mon_b = to_monomial(b)

    mon_b = %{mon_b | factors: for({f, e} <- mon_b.factors, into: %{}, do: {f, -e})}

    new_factors = Map.merge(mon_a.factors, mon_b.factors, fn _key, a_i, b_i -> a_i + b_i end)
    %Monomial{factors: simplify_monomial_terms(new_factors)}
  end

  def example() do
    s1 = %Subscripted{
      expression: %Variable{name: "x"},
      indices: [%Variable{name: "i"}]
    }

    v1 = %Variable{name: "sigma"}
    v2 = %Variable{name: "mu"}

    s = subtract(add(s1, add(v1, v2)), s1)

    divide(multiply(s1, s1), v1)
  end

  # def sub(a, b) do
  #   poly_a = to_polynomial(a)
  #   poly_b = to_polynomial(b)

  #   new_terms = Map.merge(poly_a.terms, poly_b.terms, fn a_i, b_i -> a_i + b_i end)
  #   %Polynomial{terms: simplify_polynomial_terms(new_terms)}
  # end

  # def mul(a, b) do
  #   poly_a = to_polynomial(a)
  #   poly_b = to_polynomial(b)

  #   new_terms =
  #     for {a_i, ca_i} <- poly_a, {b_i, cb_i} <- poly_b do
  #       {a_i ++ b_i, ca_i * cb_i}
  #     end

  #   grouped = Enum.group_by(new_terms, fn {key, _value} -> key end)

  #   final_terms = for {monomial, }

  #   new_terms = Map.merge(a.terms, b.terms, fn a_i, b_i -> a_i + b_i end)

  #   %Polynomial{terms: simplify_polynomial_terms(new_terms)}
  # end

  # def div(%Polynomial{} = a, %Polynomial{} = b) do
  #   new_terms = Map.merge(a.terms, b.terms, fn a_i, b_i -> a_i + b_i end)
  #   %Polynomial{terms: simplify_polynomial_terms(new_terms)}
  # end
end
