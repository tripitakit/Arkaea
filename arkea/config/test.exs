import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :arkea, Arkea.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "arkea_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :arkea, ArkeaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RjEhD2sVW0ryC0Yy1iCMNMkoqjIRp4IdAw6xJqI4mMJba5qDqdLNwEJDR62mFAiU",
  server: false

# WorldClock tick interval in ms. Set to a large value in tests so that the
# supervised WorldClock process does not fire during the test suite. Biotope.Server
# integration tests drive ticks via `manual_tick` (GenServer.call :manual_tick)
# and subscribe to PubSub directly when testing the clock-driven path.
config :arkea, :tick_interval_ms, 600_000
config :arkea, :persistence_enabled, false

config :arkea, Arkea.Oban,
  repo: Arkea.Repo,
  plugins: false,
  queues: [snapshots: 5],
  testing: :manual

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
