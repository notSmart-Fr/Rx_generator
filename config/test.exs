import Config
config :ash, disable_async?: true, policies: [show_policy_breakdowns?: true]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :rx_generator, RxGenerator.Repo,
  database: Path.expand("../rx_generator_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rx_generator, RxGeneratorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "UQ02kbFgvrmWNs4ziQASxHMPhxujXKcIeMloAVKUxmcGeoCknBgbqOHR9ao73eXg",
  server: false

# In test we don't send emails
config :rx_generator, RxGenerator.Mailer, adapter: Swoosh.Adapters.Test

# Test double mock spooler
config :rx_generator, :print_spooler, RxGenerator.Printing.MockSpooler

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
