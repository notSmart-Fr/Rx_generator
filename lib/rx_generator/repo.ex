defmodule RxGenerator.Repo do
  use AshSqlite.Repo,
    otp_app: :rx_generator

  # Let Ash wrap write actions in a transaction, so a multi-step action
  # rolls back as a unit. Requires a non-zero `busy_timeout`, which the
  # driver sets by default.
  @impl true
  def write_transactions?, do: true
end
