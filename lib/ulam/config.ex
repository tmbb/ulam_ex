defmodule Ulam.Config do
  def cmdstan_directory() do
    case Application.get_env(:ulam, :cmdstan_directory) do
      nil ->
        Path.join([System.fetch_env!("CONDA_PREFIX"), "bin", "cmdstan"])

      other ->
        other
    end
  end

  def default_model_cache(model) do
    dir =
      Path.join([
        "ulam_models",
        "CACHE",
        :crypto.hash(:sha, model.code) |> Base.encode32()
      ])

    File.mkdir_p!(dir)

    dir
  end
end
