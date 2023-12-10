# Ulam

Elixir interface to [Stan](https://mc-stan.org/), inspired by
the Python project [CmdStanPy](https://mc-stan.org/cmdstanpy/).
Why should Python programmers have all the Bayesian fun?

## Why?

I'm interested in developping probabilistic programming languages
that compile to Stan. I have found that doing so in Python is pretty
inconvenient. I have decided to give Elixir a try to see how far I can go.

## Installation

The package must be installed from GitHub.
It's not currently stable enough to be uploaded to Hex.

## Examples

Se the example in the tests.
Relevant code:

```elixir
alias Ulam.Stan.StanModel

# Some simple data for the model
data = %{
  N: 10,
  y: [0, 1, 0, 0, 0, 0, 0, 0, 0, 1]
}

# Compile the model from the stan program file
model = StanModel.compile_file("test/stan/models/bernoulli/bernoulli.stan")

# Sample from the model and save it in a dataframe
dataframe =
  StanModel.sample(model, data,
    nr_of_samples: 1000,
    nr_of_warmup_samples: 1000,
    nr_of_chains: 8,
    show_progress_bars: false
  )
```

