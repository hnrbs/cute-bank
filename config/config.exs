# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :transaction_system,
  ecto_repos: [TransactionSystem.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :transaction_system, TransactionSystemWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: TransactionSystemWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TransactionSystem.PubSub,
  live_view: [signing_salt: "zr5OGp86"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :transaction_system, TransactionSystemWeb.Auth.Guardian,
  issuer: "transaction_system",
  secret_key: "vuPhpgT65Nw2fZzqR2/mglPtawL5rsP1AjTmnx9kb5Onv4PuyAirTr/DeKAA4MyP"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
