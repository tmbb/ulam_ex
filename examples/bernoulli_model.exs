defmodule Ulam.Examples.BernoulliModel do
  require Ulam.UlamModel, as: UlamModel

  stan_file = "examples/bernoulli_model/bernouli_model.stan"

  # Define the model using Elixir AST.
  # The format follows tha Stan language pretty closely.
  # One can also define the model dynamically using the structs
  # under the UlamAST module.
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

  # Cache the model and ensure compilation happens at compile-time
  @ulam_model UlamModel.compile(ulam_model)

  def run() do
    # In real life you'd read this from a file
    data = %{
      n: 10,
      y: [0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
    }

    # Sample from the precompiled model
    dataframe =
      UlamModel.sample(@ulam_model, data,
        nr_of_samples: 1000,
        nr_of_warmup_samples: 1000,
        nr_of_chains: 8
      )

    dataframe
  end
end

Ulam.Examples.BernoulliModel.run()
