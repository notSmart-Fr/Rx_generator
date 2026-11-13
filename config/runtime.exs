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
#     PHX_SERVER=true bin/rx_generator start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :rx_generator, RxGeneratorWeb.Endpoint, server: true
end

port =
  case System.get_env("PORT") do
    nil -> 4000
    "" -> 4000
    val -> String.to_integer(val)
  end

config :rx_generator, RxGeneratorWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: port
  ]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :rx_generator, RxGeneratorWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/rx_generator_web/router\.ex$"E,
        ~r"lib/rx_generator_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # In release / desktop mode, automatically resolve data directory, database, and secrets if unset
  if System.get_env("RELEASE_NAME") != nil and
       (System.get_env("DATABASE_PATH") == nil or System.get_env("SECRET_KEY_BASE") == nil) do
    data_dir = RxGenerator.Release.resolve_user_data_dir()
    RxGenerator.Release.ensure_user_data_dir(data_dir)

    template_db =
      if Code.ensure_loaded?(RxGenerator.Release) do
        RxGenerator.Release.resolve_template_db_path()
      else
        Path.expand("../priv/repo/seeds/rx_generator_seed.db", __DIR__)
      end

    working_db = Path.join(data_dir, "rx_generator.db")
    RxGenerator.Release.ensure_database_file(working_db, template_db)

    secrets = RxGenerator.Release.ensure_secrets(data_dir)

    System.put_env("DATABASE_PATH", working_db)
    System.put_env("SECRET_KEY_BASE", secrets.secret_key_base)
    System.put_env("CLOAK_KEY", secrets.cloak_key)
  end

  build_time? = System.get_env("RELEASE_NAME") == nil

  database_path =
    System.get_env("DATABASE_PATH") ||
      if(build_time?,
        do: Path.expand("../priv/repo/seeds/rx_generator_seed.db", __DIR__),
        else:
          raise("""
          environment variable DATABASE_PATH is missing.
          For example: /etc/rx_generator/rx_generator.db
          """)
      )

  config :rx_generator, RxGenerator.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      if(build_time?,
        do: String.duplicate("rx_generator_build_time_placeholder_key_", 2),
        else:
          raise("""
          environment variable SECRET_KEY_BASE is missing.
          You can generate one by calling: mix phx.gen.secret
          """)
      )

  host = System.get_env("PHX_HOST") || "example.com"

  config :rx_generator, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  prod_port =
    case System.get_env("PORT") do
      nil -> 0
      "" -> 0
      val -> String.to_integer(val)
    end

  config :rx_generator, RxGeneratorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {127, 0, 0, 1},
      port: prod_port
    ],
    secret_key_base: secret_key_base

  if cloak_env = System.get_env("CLOAK_KEY") do
    cloak_key =
      case Base.decode64(cloak_env) do
        {:ok, decoded} when byte_size(decoded) == 32 -> decoded
        _ when byte_size(cloak_env) == 32 -> cloak_env
        _ -> nil
      end

    if cloak_key do
      config :rx_generator, RxGenerator.Vault,
        json_library: Jason,
        ciphers: [
          default: {
            Cloak.Ciphers.AES.GCM,
            tag: "AES.GCM.V1", key: cloak_key, iv_length: 12
          }
        ]
    end
  end

  if System.get_env("RELEASE_NAME") != nil do
    config :rx_generator, RxGenerator.Formulary.NeuralWorker,
      model_path: Application.app_dir(:rx_generator, "priv/models/embedding_gemma_2"),
      dimension: 256
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :rx_generator, RxGeneratorWeb.Endpoint,
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
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :rx_generator, RxGeneratorWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :rx_generator, RxGenerator.Mailer,
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
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
