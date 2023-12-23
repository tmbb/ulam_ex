defmodule Ulam.TestSupport do
  alias ExUnit.Callbacks
  require ExUnit.Assertions, as: Assertions

  def remove_stan_compiled_artifacts(directories) do
    do_remove_stan_compiled_artifacts(directories)
    Callbacks.on_exit(fn ->
      do_remove_stan_compiled_artifacts(directories)
    end)
  end

  def clean_directories(directories) do
    do_clean_directories(directories)
    Callbacks.on_exit(fn ->
      do_clean_directories(directories)
    end)
  end

  def cross_platform_assert_equal(left, right) do
    canonical_left = String.replace(left, "\r\n", "\n")
    canonical_right = String.replace(right, "\r\n", "\n")

    Assertions.assert(canonical_left == canonical_right)
  end

  defp do_clean_directories(directories) do
    for directory <- directories do
      for relative_path <- File.ls!(directory) do
        # Remove everything except the .gitkeep file
        unless relative_path == ".gitkeep" do
          full_path = Path.join(directory, relative_path)
          File.rm!(full_path)
        end
      end
    end
  end

  defp do_remove_stan_compiled_artifacts(directories) do
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
end
