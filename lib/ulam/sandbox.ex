defmodule Ulam.Sandbox do
  require Explorer.DataFrame, as: DataFrame
  alias Explorer.Series

  alias Ulam.Stan.StanModel

  def test() do
    data = %{
      N: 10,
      y: [0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    }

    model = StanModel.compile_file("lib/ulam/sandbox/bernoulli/bernoulli.stan")
    df = StanModel.sample(model, data)
    theta = df["theta"]
    kde(theta, 200)
  end

  def default_bandwidth(series) do
    n = Series.size(series)
    sigma_hat = Series.standard_deviation(series)
    q1 = Series.quantile(series, 0.25)
    q3 = Series.quantile(series, 0.75)
    iqr = q3 - q1

    0.9 * min(sigma_hat, iqr / 1.34) * n ** (-1 / 5)
  end

  def linear_space_list(a, b, n) do
    step = (b - a) / n
    [a | Enum.reverse(Enum.map(0..(n - 2), fn i -> b - i * step end))]
  end

  def linear_space(a, b, n) do
    Series.from_list(linear_space_list(a, b, n))
  end

  defguardp one_is_series(a, b) when is_struct(a, Series) or is_struct(b, Series)

  @doc false
  def maybe_series_add(a, b) when one_is_series(a, b), do: Series.add(a, b)
  def maybe_series_add(a, b), do: a + b

  @doc false
  def maybe_series_subtract(a, b) when one_is_series(a, b), do: Series.subtract(a, b)
  def maybe_series_subtract(a, b), do: a - b

  @doc false
  def maybe_series_multiply(a, b) when one_is_series(a, b), do: Series.multiply(a, b)
  def maybe_series_multiply(a, b), do: a * b

  @doc false
  def maybe_series_divide(a, b) when one_is_series(a, b), do: Series.divide(a, b)
  def maybe_series_divide(a, b), do: a / b

  @doc false
  def maybe_series_pow(a, b) when one_is_series(a, b), do: Series.pow(a, b)
  def maybe_series_pow(a, b), do: a ** b

  @doc false
  def maybe_series_minus(s) when is_struct(s, Series), do: Series.subtract(0, s)
  def maybe_series_minus(a), do: -a

  @doc false
  def maybe_series_exp(s) when is_struct(s, Series), do: Series.exp(s)
  def maybe_series_exp(a), do: :math.exp(a)

  defmacro series!(do: body) do
    new_ast =
      Macro.prewalk(body, fn ast_node ->
        case ast_node do
          {:+, _meta, [left, right]} ->
            quote do
              unquote(__MODULE__).maybe_series_add(unquote(left), unquote(right))
            end

          {:-, _meta, [left, right]} ->
            quote do
              unquote(__MODULE__).maybe_series_subtract(unquote(left), unquote(right))
            end

          {:*, _meta, [left, right]} ->
            quote do
              unquote(__MODULE__).maybe_series_multiply(unquote(left), unquote(right))
            end

          {:/, _meta, [left, right]} ->
            quote do
              unquote(__MODULE__).maybe_series_divide(unquote(left), unquote(right))
            end

          {:**, _meta, [left, right]} ->
            quote do
              unquote(__MODULE__).maybe_series_pow(unquote(left), unquote(right))
            end

          {:-, _meta, [value]} ->
            quote do
              unquote(__MODULE__).maybe_series_minus(unquote(value))
            end

          {:exp, _meta, [value]} ->
            quote do
              unquote(__MODULE__).maybe_series_exp(unquote(value))
            end

          {:sum, _meta, [series]} ->
            quote do
              Explorer.Series.sum(unquote(series))
            end

          other ->
            other
        end
      end)

    new_ast
  end

  @inv_sqrt_2pi 1 / :math.sqrt(2 * :math.pi())

  def gaussian_kernel(x, observations, bandwidth) do
    # Series.multiply(
    #   @inv_sqrt_2pi,
    #   Series.exp(
    #     Series.multiply(
    #       0.5,
    #       Series.subtract(
    #         0.0,
    #         Series.pow(
    #           Series.divide(
    #             Series.subtract(x, observations),
    #             bandwidth
    #           ),
    #           2
    #         )
    #       )
    #     )
    #   )
    # )

    series! do
      @inv_sqrt_2pi * exp(-0.5 * ((x - observations) / bandwidth) ** 2)
    end
  end

  def kde(observations, n, opts \\ []) do
    kernel = Keyword.get(opts, :kernel, &gaussian_kernel/3)
    n_observations = Series.size(observations)
    min = Series.min(observations)
    max = Series.max(observations)
    # Estimate the bandwidth
    bandwidth = default_bandwidth(observations)
    # Get the x points at which we want to draw
    xs = linear_space_list(min, max, n)

    ys =
      for x_i <- xs do
        Series.sum(kernel.(x_i, observations, bandwidth)) / (n_observations * bandwidth)
      end

    DataFrame.new(x: xs, y: ys)
  end

  def example1() do
    quote do
      data do
        n :: int(lower: 0)
        disasters :: array(n, int(lower: 0))
      end

      parameters do
        changepoint :: int(lower: 0, upper: 0)
        early_rate :: real()
        late_rate :: real()
      end

      model do
        for t <- 1..n do
          cond do
            t < changepoint ->
              disasters[t] <~> poisson(early_rate)

            true ->
              disasters[t] <~> poisson(late_rate)
          end
        end
      end
    end
  end

  def example() do
    quote do
      n :: data(int())
      x :: data(vector(n), missing: true)
      y :: data(vector(n), missing: true, log_lik: true)

      slope :: parameter(real())
      intercept :: parameter(real())
      error :: parameter(real(lower: 0))
      p :: parameter(real(lower: 0, upper: 1))

      log_lik :: generated(vector(n))

      for i <- 1..n do
        y[i] <~> normal(x[i] * slope + intercept, error)
        y[i] <~> right_censored_weibul(x[i] * slope + intercept, lambda, event[i])
      end
    end
  end
end
