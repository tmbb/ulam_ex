defmodule Ulam.Nutex.Math.Operators do
  import Kernel, except: [+: 2, -: 2, *: 2, /: 2]

  defmacro __using__(_opts \\ []) do
    quote do
      import Kernel, except: [+: 2, -: 2, *: 2, /: 2, -: 1]
      import Ulam.Nutex.Math.Operators, only: [+: 2, -: 2, *: 2, /: 2, -: 1]
    end
  end

  def a + b do
    Ulam.Nutex.Math.add(a, b)
  end

  def a - b do
    Ulam.Nutex.Math.sub(a, b)
  end

  def a * b do
    Ulam.Nutex.Math.mul(a, b)
  end

  def a / b do
    Ulam.Nutex.Math.div(a, b)
  end

  def -a do
    Ulam.Nutex.Math.sub(0, a)
  end
end
