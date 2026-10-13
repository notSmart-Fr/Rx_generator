[
  import_deps: [
    :cinder,
    :ash_state_machine,
    :ash,
    :reactor,
    :ash_admin,
    :ash_sqlite,
    :ash_phoenix,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
