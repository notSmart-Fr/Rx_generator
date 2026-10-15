Application.put_env(:rx_generator, :print_spooler, RxGenerator.Printing.MockSpooler)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(RxGenerator.Repo, :manual)
