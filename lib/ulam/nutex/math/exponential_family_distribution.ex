defmodule Ulam.Nutex.Math.ExponentialFamilyDistribution do
  alias Ulam.Nutex.Math
  use Ulam.Nutex.Math.Operators

  defstruct name: nil,
            parameters: [],
            natural_parameters: [],
            base_measure: nil,
            sufficient_statistic: nil,
            log_partition: nil

  def normal(x, loc, scale) do
    %__MODULE__{
      name: "Normal",
      parameters: [
        loc / scale,
        -(1 / (2 * scale))
      ],
      base_measure: 1 / :math.sqrt(2 * :math.pi()),
      sufficient_statistic: [
        x,
        x * x
      ],
      log_partition: loc * loc / (2 * scale) + Math.log(Math.sqrt(scale))
    }
  end
end
