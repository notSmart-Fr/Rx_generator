if Code.ensure_loaded?(Mox) do
  Mox.defmock(RxGenerator.Printing.MockSpooler, for: RxGenerator.Printing.Spooler)
end
