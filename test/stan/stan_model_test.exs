defmodule Ulam.Stan.StanModelTest do
  use ExUnit.Case, async: true

  alias Ulam.Stan.StanModel
  alias Explorer.DataFrame

  defp remove_all_compiled_artifacts() do
    directories = [
      "test/stan/models/bernoulli"
    ]

    for directory <- directories do
      for relative_path <- File.ls!(directory) do
        # Remove all compiled artifacts
        unless Path.extname(relative_path) == ".stan" do
          full_path = Path.join(directory, relative_path)
          File.rm!(full_path)
        end
      end
    end
  end

  setup do
    remove_all_compiled_artifacts()
    on_exit(&remove_all_compiled_artifacts/0)
  end

  test "compile and run bernoulli model" do
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

    assert %DataFrame{} = dataframe
    # The number of rows is the number of chains times the number of samples per chain.
    # warmup samples have been discarded (the default)
    assert DataFrame.n_rows(dataframe) == 8 * 1000
    # The parameter is one of the columns
    assert "theta" in DataFrame.names(dataframe)
    # The log-likelihood is one of the columns
    assert "lp__" in DataFrame.names(dataframe)
    # The chain_id is one of the columns
    assert "chain_id__" in DataFrame.names(dataframe)
  end
end
