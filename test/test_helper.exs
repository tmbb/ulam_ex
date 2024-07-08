exclude_slow? = true

if exclude_slow? do
  ExUnit.start(exclude: [slow: true])
else
  ExUnit.start()
end
