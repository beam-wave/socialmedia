import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/socialmedia start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :socialmedia, SocialmediaWeb.Endpoint, server: true
end

# Load KEY=value lines from .env (real env vars win). Not used in tests.
env_file = Path.expand("../.env", __DIR__)

if config_env() != :test and File.exists?(env_file) do
  for line <- File.read!(env_file) |> String.split("\n"),
      line = String.trim(line),
      line != "" and not String.starts_with?(line, "#"),
      [k, v] <- [String.split(line, "=", parts: 2)],
      System.get_env(String.trim(k)) == nil do
    System.put_env(String.trim(k), v |> String.trim() |> String.trim("\""))
  end
end

truthy? = fn name, default -> System.get_env(name, default) in ~w(true 1 yes) end

# Node roles (see Socialmedia.Flags). Prod and the Mac only talk through S3.
#   prod: PRIMARY=true  CONTENT=false PUBLISH=true  S3_PREFIX=prod
#   Mac:  PRIMARY=false CONTENT=true  PUBLISH=false S3_PREFIX=prod  (makes content for prod)
#   dev:  PRIMARY=true  CONTENT=true  PUBLISH=false S3_PREFIX=dev   (everything on one machine)
primary? = truthy?.("PRIMARY", "true")
content? = truthy?.("CONTENT", "false")
publish? = truthy?.("PUBLISH", "false")

if config_env() != :test do
  config :socialmedia,
    primary: primary?,
    content: content?,
    publish: publish?,
    storage: Socialmedia.Storage.S3,
    storage_prefix: System.get_env("S3_PREFIX", to_string(config_env()))

  config :socialmedia, Socialmedia.Storage.S3,
    bucket: System.get_env("S3_BUCKET"),
    region: System.get_env("AWS_REGION", "ap-south-1"),
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    endpoint: System.get_env("S3_ENDPOINT")

  crontab =
    if(primary?,
      do: [
        {"0 1 * * *", Socialmedia.Workers.Planner},
        {"*/5 * * * *", Socialmedia.Workers.Expirer},
        {"*/2 * * * *", Socialmedia.Workers.SyncBus}
      ],
      else: []
    ) ++
      if(primary? and publish?, do: [{"0 3 * * 1", Socialmedia.Workers.RefreshTokens}], else: []) ++
      if(content?, do: [{"*/3 * * * *", Socialmedia.Workers.ContentPoller}], else: [])

  oban = Application.get_env(:socialmedia, Oban)

  config :socialmedia, Oban,
    plugins: oban[:plugins] ++ [{Oban.Plugins.Cron, crontab: crontab}],
    queues:
      [planner: 1] ++
        if(primary?, do: [publish: 3, maintenance: 1], else: []) ++
        if(content?, do: [claude: 1], else: [])
end

# Basic auth for the admin panel (/media stays public so Instagram can fetch slides).
config :socialmedia,
  admin_user: System.get_env("ADMIN_USER", "admin"),
  admin_password: System.get_env("ADMIN_PASSWORD")

if root = System.get_env("PROJECT_ROOT") do
  config :socialmedia, project_root: root
end

if config_env() == :prod do
  config :socialmedia,
    cloak_key:
      System.get_env("CLOAK_KEY") ||
        raise("CLOAK_KEY is missing. Generate one with: openssl rand -base64 32")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :socialmedia, Socialmedia.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :socialmedia, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :socialmedia, SocialmediaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :socialmedia, SocialmediaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :socialmedia, SocialmediaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :socialmedia, Socialmedia.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
