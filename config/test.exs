import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :socialmedia, Socialmedia.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "socialmedia_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :socialmedia, SocialmediaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "J+CfLeU7aLMtTD6yFP9asf4yk07ExMDv/avrf/LUvmUme2j6i9BDAB4h+wOUPvz4",
  server: false

# In test we don't send emails
config :socialmedia, Socialmedia.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :socialmedia, Oban, testing: :manual
config :socialmedia, cloak_key: "1QVGJkE0nBwNq7fgSrJk8EYb2lX4lD0vZz0qP6Xr6Gk="
config :socialmedia, Socialmedia.Instagram.Graph, plug: {Req.Test, Socialmedia.Instagram.Graph}
config :socialmedia, admin_auth: false

config :socialmedia,
  graph_poll_ms: 0,
  storage: Socialmedia.Storage.Local,
  storage_prefix: "test",
  local_storage_dir: Path.expand("../tmp/test_storage", __DIR__)
