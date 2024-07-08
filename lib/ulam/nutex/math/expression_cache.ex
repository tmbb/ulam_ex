defmodule Ulam.Nutex.Math.ExpressionCache do
  defstruct summations: %{},
            count: 0

  alias Ulam.Nutex.Math.RFrac
  alias Ulam.Nutex.Math.Compiler

  def polynomial_to_part_of_variable_name(poly) do
    sorted = Enum.sort(poly)

    terms =
      Enum.map(sorted, fn {factors, coef} ->
        all_factors =
          case coef do
            one when one in [1, 1.0] -> factors
            _other -> [coef | factors]
          end

        all_factors
        |> Enum.map(fn e -> Compiler.to_rust(e, no_cache_no_data: true) end)
        |> Enum.intersperse("_times_")
      end)

    terms
    |> Enum.intersperse("_plus_")
    |> List.flatten()
    |> Enum.join()
  end

  def rfrac_to_slug(%RFrac{} = rfrac) do
    before_slugification =
      if RFrac.proper_polynomial?(rfrac) do
        polynomial_to_part_of_variable_name(rfrac.num)
      else
        num = polynomial_to_part_of_variable_name(rfrac.num)
        den = polynomial_to_part_of_variable_name(rfrac.den)
        "#{num}_divided_by_#{den}"
      end

    Slug.slugify(before_slugification, separator: "_")
  end

  def add_summation(cache, rfrac, index, limit) do
    case Map.fetch(cache.summations, rfrac) do
      # We already have a variable for this summation
      {:ok, {variable_name, _index_limit}} ->
        {cache, variable_name}

      # Create a new variable in the cache
      :error ->
        slug = rfrac_to_slug(rfrac)
        variable_name = "sum_of_#{slug}__#{cache.count}"

        summations = Map.put(cache.summations, rfrac, {variable_name, {index, limit}})
        new_cache = %{cache | count: cache.count + 1, summations: summations}

        {new_cache, variable_name}
    end
  end
end
