defmodule Ulam.Nutex.Math.Compiler do
  alias Ulam.Nutex.Math.{
    RFrac,
    Variable,
    Subscripted,
    TypeCast,
    Func
  }

  alias Inspect.Algebra, as: IAlgebra

  @default_document_width 80

  def monomial_to_signed_rust_algebra(monomial, opts) do
    {factors, coef} = monomial

    {sign, coef} =
      case coef do
        number when is_number(number) ->
          if coef < 0 do
            {:-, abs(coef)}
          else
            {:+, coef}
          end

        _other ->
          {:+, coef}
      end

    all_factors =
      case coef do
        one when one in [1, 1.0] -> factors
        _other -> [coef | factors]
      end

    doc =
      if length(all_factors) == 1 do
        [factor] = all_factors
        to_rust_algebra(factor, opts)
      else
        IAlgebra.container_doc(
          "",
          all_factors,
          "",
          opts,
          fn factor, opts -> to_rust_algebra(factor, opts) end,
          separator: " *"
        )
      end

    {sign, doc}
  end

  def monomial_inside_polynomial_to_rust_algebra(monomial, 0, opts) do
    {sign, doc} = monomial_to_signed_rust_algebra(monomial, opts)

    case sign do
      :+ ->
        doc

      :- ->
        IAlgebra.group(IAlgebra.concat(["- ", doc]))
    end
  end

  def monomial_inside_polynomial_to_rust_algebra(monomial, index, opts) when index != 0 do
    {sign, doc} = monomial_to_signed_rust_algebra(monomial, opts)

    case sign do
      :+ ->
        IAlgebra.concat(["+ ", doc])

      :- ->
        IAlgebra.group(IAlgebra.concat(["- ", doc]))
    end
  end

  def polynomial_to_rust_algebra(poly, opts) when map_size(poly) == 1 do
    [monomial] = Enum.into(poly, [])
    {sign, doc} = monomial_to_signed_rust_algebra(monomial, opts)

    case sign do
      :+ ->
        IAlgebra.group(IAlgebra.concat(["(", doc, ")"]))

      :- ->
        IAlgebra.group(IAlgebra.concat(["(", "- ", doc, ")"]))
    end
  end

  def polynomial_to_rust_algebra(poly, opts) do
    # Sort the monomials to ensure reproducible results
    sorted_monomials =
      poly
      |> Enum.into([])
      |> Enum.sort()

    # We'll need to be able to distinguish the first monomial from the others
    indexed_monomials = Enum.with_index(sorted_monomials, 0)

    IAlgebra.container_doc(
      "(",
      indexed_monomials,
      ")",
      opts,
      fn {monomial, index}, opts ->
        monomial_inside_polynomial_to_rust_algebra(monomial, index, opts)
      end,
      separator: ""
    )
  end

  def to_rust_algebra(number, opts \\ %Inspect.Opts{})

  def to_rust_algebra(number, _opts) when is_number(number) do
    inspect(number)
  end

  def to_rust_algebra(%Variable{} = variable, opts) do
    case Keyword.get(opts.custom_options, :no_cache_no_data) do
      true ->
        variable.name

      _other ->
        case {variable.cache, variable.kind} do
          {true, _} ->
            "self.cache.#{variable.name}"

          {false, :data} ->
            "self.data.#{variable.name}"

          {false, _} ->
            variable.name
        end
    end
  end

  def to_rust_algebra(%TypeCast{} = type_cast, opts) do
    IAlgebra.group(
      IAlgebra.concat([
        "(",
        to_rust_algebra(type_cast.value, opts),
        " as ",
        type_cast.type,
        ")"
      ])
    )
  end

  # Assume there is only a single index
  def to_rust_algebra(%Subscripted{subscripts: [index]} = subscripted, opts) do
    IAlgebra.group(
      IAlgebra.concat([
        to_rust_algebra(subscripted.expression, opts),
        "[",
        to_rust_algebra(index),
        "]"
      ])
    )
  end

  def to_rust_algebra(%Func{method: true, args: [first_arg | args]} = func, opts) do
    IAlgebra.concat([
      to_rust_algebra(first_arg),
      ".",
      func.name,
      IAlgebra.container_doc(
        "(",
        args,
        ")",
        opts,
        fn monomial, opts -> to_rust_algebra(monomial, opts) end,
        separator: ","
      )
    ])
  end

  def to_rust_algebra(%Func{} = func, opts) do
    IAlgebra.concat([
      func.name,
      IAlgebra.container_doc(
        "(",
        func.args,
        ")",
        opts,
        fn monomial, opts -> to_rust_algebra(monomial, opts) end,
        separator: ","
      )
    ])
  end

  def to_rust_algebra(%RFrac{} = rfrac, opts) do
    if rfrac.den == %{[] => 1} or rfrac.den == %{[] => 1.0} do
      polynomial_to_rust_algebra(rfrac.num, opts)
    else
      IAlgebra.group(
        IAlgebra.concat([
          polynomial_to_rust_algebra(rfrac.num, opts),
          " / ",
          polynomial_to_rust_algebra(rfrac.den, opts)
        ])
      )
    end
  end

  def to_rust(expression, opts \\ []) do
    no_cache_no_data = Keyword.get(opts, :no_cache_no_data, false)
    width = Keyword.get(opts, :width, @default_document_width)

    inspect_options = %Inspect.Opts{
      limit: :infinity,
      custom_options: [
        no_cache_no_data: no_cache_no_data
      ]
    }

    doc = to_rust_algebra(expression, inspect_options)

    doc
    |> IAlgebra.format(width)
    |> IO.iodata_to_binary()
  end

  def to_rust_plain_vars(expression) do
    to_rust(expression, no_cache_no_data: true)
  end
end
