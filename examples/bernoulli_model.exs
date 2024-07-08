defmodule Ulam.Examples.BernoulliModel do
  require Ulam.UlamModel, as: UlamModel
  require Explorer.DataFrame, as: DataFrame
  alias Explorer.Series
  alias Ulam.Sandbox

  alias Quartz.{Figure, Length, Plot2D}
  alias Quartz.Color.RGB
  use Dantzig.Polynomial.Operators

  # The user has to give an explicit filename for the generated Stan code.
  # Alternatively, the user can give just a filename and a directory
  # with that name containing the stan file will be created under
  # `ulam_models/`. Here we choose to give an explicit name.
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
        nr_of_chains: 4
      )

    DataFrame.to_parquet!(dataframe, "examples/bernoulli_model/samples.parquet")
  end

  def visualize() do
    samples = DataFrame.from_parquet!("examples/bernoulli_model/samples.parquet")

    figure_attributes = [
      width: Length.cm(8),
      height: Length.cm(6)
    ]

    colors = [
      RGB.hot_pink(0.4),
      RGB.dark_violet(0.4),
      RGB.medium_blue(0.4),
      RGB.dark_red(0.4)
    ]

    figure =
      Figure.new(figure_attributes, fn _fig ->
        theta_kdes =
          for chain_id <- 1..4 do
            theta = DataFrame.filter(samples, chain_id__ == ^chain_id)["theta"]
            Sandbox.kde(theta, 200)
          end

        plot =
          Plot2D.new(id: "plot_A")
          |> Plot2D.put_title("A. Posterior probability for $theta$ (all 4 chains)", text: [escape: false])
          |> Plot2D.put_axis_label("x", "$theta$", text: [escape: false])
          |> Plot2D.put_axis_minimum_margins("x", Length.pt(10))
          |> Plot2D.put_axis_minimum_margins("y", Length.pt(10))

        plot =
          Enum.zip(theta_kdes, colors)
          |> Enum.reduce(plot, fn {theta_kde, color}, plot ->
            x = Series.to_enum(theta_kde["x"])
            y = Series.to_enum(theta_kde["y"])

            Plot2D.line_plot(plot, x, y, style: [color: color])
          end)

        Plot2D.finalize(plot)
      end)

    path = Path.join([__DIR__, "bernoulli_model", "theta.pdf"])
    Figure.render_to_pdf_file!(figure, path)
  end
end

# Ulam.Examples.BernoulliModel.run()
Ulam.Examples.BernoulliModel.visualize()
