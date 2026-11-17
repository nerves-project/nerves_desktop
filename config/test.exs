import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_desktop, NervesDesktopWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4zQWNCEeIMRtfeiyIv5x52S+jnKyYWst29iR03G226szLk3qMqkuZLJkT6pJxRuN",
  server: false

# Keep test MCP servers off the real ports and out of the user's saved state
config :nerves_desktop, NervesDesktop.MCP,
  path: nil,
  ports: 23_600..23_699,
  log_dir: Path.join([System.tmp_dir!(), "nerves_desktop_test", "mcp"])

# In test we don't send emails
config :nerves_desktop, NervesDesktop.Mailer, adapter: Swoosh.Adapters.Test

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
