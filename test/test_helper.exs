excludes = [:integration]
excludes = if match?({:win32, _}, :os.type()), do: [:unix_only | excludes], else: excludes

ExUnit.start(exclude: excludes)
