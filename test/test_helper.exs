exclude_slow? = false

if exclude_slow? do
  ExUnit.start(exclude: [slow: true])
else
  ExUnit.start()
end
