defmodule Ulam.Stan.ChainRunnerArgs do
  defstruct model_executable: nil,
            data_file: nil,
            output_path: nil,
            nr_of_samples: nil,
            nr_of_warmup_samples: nil,
            refresh_every: nil,
            chain_id: nil,
            random_seed: nil,
            progress_bar_id: nil
end
