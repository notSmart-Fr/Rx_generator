defmodule RxGenerator.Release do
  @moduledoc """
  Responsible for provisioning and bootstrapping the local runtime environment
  for standalone desktop distributions:
  - Resolving OS-specific user data directory (%APPDATA% or ~/.local/share)
  - Copying bundled pre-seeded SQLite formulary database
  - Generating and storing persistent node secrets (SECRET_KEY_BASE, CLOAK_KEY)
  - Running Ash / Ecto database migrations safely
  """

  @app :rx_generator

  @doc """
  Full bootstrap sequence invoked before OTP application and endpoint start.
  """
  def bootstrap do
    data_dir = resolve_user_data_dir()
    ensure_user_data_dir(data_dir)

    template_db = resolve_template_db_path()
    working_db = Path.join(data_dir, "rx_generator.db")
    ensure_database_file(working_db, template_db)

    secrets = ensure_secrets(data_dir)

    System.put_env("DATABASE_PATH", working_db)
    System.put_env("SECRET_KEY_BASE", secrets.secret_key_base)
    System.put_env("CLOAK_KEY", secrets.cloak_key)

    run_migrations()
  end

  def resolve_template_db_path do
    candidate = Application.app_dir(@app, "priv/repo/seeds/rx_generator_seed.db")

    if File.exists?(candidate) and File.stat!(candidate).size > 0 do
      candidate
    else
      # In dev/test or custom release layout, search relative to priv
      fallback = Path.expand("../priv/repo/seeds/rx_generator_seed.db", __DIR__)

      if File.exists?(fallback) and File.stat!(fallback).size > 0 do
        fallback
      else
        priv = :code.priv_dir(@app)

        if is_list(priv) or is_binary(priv) do
          Path.join(priv, "repo/seeds/rx_generator_seed.db")
        else
          fallback
        end
      end
    end
  end

  @doc """
  Resolves the standard OS user data directory:
  - Windows: %APPDATA%/RxGenerator
  - Linux/Unix: $XDG_DATA_HOME/rx_generator or ~/.local/share/rx_generator
  """
  def resolve_user_data_dir do
    case :os.type() do
      {:win32, _} ->
        base = System.get_env("APPDATA") || System.user_home!()
        Path.join(base, "RxGenerator")

      {:unix, _} ->
        base =
          System.get_env("XDG_DATA_HOME") ||
            Path.join(System.user_home!(), ".local/share")

        Path.join(base, "rx_generator")
    end
  end

  @doc """
  Ensures the target user data directory exists.
  """
  def ensure_user_data_dir(dir) do
    File.mkdir_p!(dir)
    :ok
  end

  @doc """
  Provisions the working database from the seed template if absent.
  """
  def ensure_database_file(dest_path, template_path) do
    if File.exists?(dest_path) and File.stat!(dest_path).size > 0 do
      :ok
    else
      if File.exists?(template_path) and File.stat!(template_path).size > 0 do
        File.copy!(template_path, dest_path)
      else
        # Seed from dgda_sample.csv if template db isn't pre-generated
        csv_seed = resolve_csv_seed_path()

        if File.exists?(csv_seed) do
          seed_database_from_csv(dest_path, csv_seed)
        else
          File.touch!(dest_path)
        end
      end

      :ok
    end
  end

  def resolve_csv_seed_path do
    candidate = Application.app_dir(@app, "priv/repo/seeds/dgda_sample.csv")

    if File.exists?(candidate) do
      candidate
    else
      fallback = Path.expand("../../priv/repo/seeds/dgda_sample.csv", __DIR__)

      if File.exists?(fallback) do
        fallback
      else
        Path.expand("../../test/fixtures/dgda_sample.csv", __DIR__)
      end
    end
  end

  defp seed_database_from_csv(db_path, csv_path) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL;")

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      inserted_at TEXT
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS drug_catalog (
      id TEXT PRIMARY KEY,
      brand_name TEXT NOT NULL,
      generic_name TEXT NOT NULL,
      strength TEXT NOT NULL,
      dosage_form TEXT NOT NULL,
      manufacturer TEXT NOT NULL,
      dgda_reg_no TEXT,
      is_controlled INTEGER NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE VIRTUAL TABLE IF NOT EXISTS drug_catalog_fts USING fts5(
      brand_name,
      generic_name,
      strength,
      dosage_form,
      tokenize='trigram'
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
    END;
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TRIGGER IF NOT EXISTS drug_catalog_au AFTER UPDATE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS drug_catalog_vectors (
      id TEXT PRIMARY KEY NOT NULL,
      drug_catalog_item_id TEXT NOT NULL REFERENCES drug_catalog(id) ON DELETE CASCADE,
      embedding BLOB NOT NULL,
      dimension INTEGER NOT NULL DEFAULT 256,
      model_version TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE UNIQUE INDEX IF NOT EXISTS drug_catalog_vectors_item_id_idx
    ON drug_catalog_vectors(drug_catalog_item_id);
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE INDEX IF NOT EXISTS drug_catalog_vectors_version_idx
    ON drug_catalog_vectors(model_version);
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE TRIGGER IF NOT EXISTS validate_drug_catalog_vector_dim
    BEFORE INSERT ON drug_catalog_vectors
    BEGIN
      SELECT CASE
        WHEN NEW.dimension != 256 OR length(NEW.embedding) != 1024 THEN
          RAISE(ABORT, 'DrugCatalogVector dimension must be 256 and embedding length 1024 bytes')
      END;
    END;
    """)

    # Parse and insert seed records from CSV
    lines =
      csv_path
      |> File.stream!()
      |> Stream.drop(1)
      |> Enum.take(20)

    for line <- lines do
      parts =
        line
        |> String.trim()
        |> String.split(",")
        |> Enum.map(&(&1 |> String.trim() |> String.trim("\"")))

      if length(parts) >= 6 do
        [_sl, mfg, brand, generic, form, reg | _] = parts
        id = Ash.UUID.generate()
        vec_id = Ash.UUID.generate()
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        stmt =
          "INSERT INTO drug_catalog (id, brand_name, generic_name, strength, dosage_form, manufacturer, dgda_reg_no, is_controlled, inserted_at, updated_at) " <>
            "VALUES ('#{id}', '#{escape_sql(brand)}', '#{escape_sql(generic)}', 'standard', '#{escape_sql(form)}', '#{escape_sql(mfg)}', '#{escape_sql(reg)}', 0, '#{now}', '#{now}');"

        :ok = Exqlite.Sqlite3.execute(conn, stmt)

        embedding_hex =
          "#{brand} #{generic} #{form}"
          |> build_deterministic_embedding()
          |> Base.encode16()

        vec_stmt =
          "INSERT INTO drug_catalog_vectors (id, drug_catalog_item_id, embedding, dimension, model_version, inserted_at, updated_at) " <>
            "VALUES ('#{vec_id}', '#{id}', X'#{embedding_hex}', 256, 'embedding-gemma-2-256d', '#{now}', '#{now}');"

        :ok = Exqlite.Sqlite3.execute(conn, vec_stmt)
      end
    end

    # Record migration markers so Ecto schema_migrations recognizes pre-seeded tables
    now_ts = DateTime.utc_now() |> DateTime.to_iso8601()

    for version <- [20_261_013_075_516, 20_261_013_075_518, 20_261_015_160_000] do
      Exqlite.Sqlite3.execute(
        conn,
        "INSERT OR IGNORE INTO schema_migrations (version, inserted_at) VALUES (#{version}, '#{now_ts}');"
      )
    end

    Exqlite.Sqlite3.close(conn)
  end

  defp build_deterministic_embedding(text) do
    raw_values =
      for idx <- 0..255 do
        <<u16::unsigned-little-integer-16, _rest::binary>> =
          :crypto.hash(:sha256, "#{text}:#{idx}")

        u16 / 65_535.0 - 0.5
      end

    norm =
      raw_values
      |> Enum.reduce(0.0, fn x, acc -> acc + x * x end)
      |> :math.sqrt()
      |> max(1.0e-6)

    for x <- raw_values, into: <<>> do
      <<x / norm::float-32-little>>
    end
  end

  defp escape_sql(str) do
    String.replace(str, "'", "''")
  end

  @doc """
  Loads or generates persistent machine secrets (SECRET_KEY_BASE, CLOAK_KEY).
  """
  def ensure_secrets(dir) do
    secrets_path = Path.join(dir, "secrets.env")

    if File.exists?(secrets_path) do
      content = File.read!(secrets_path)
      lines = String.split(content, ["\r\n", "\n"], trim: true)

      map =
        Enum.reduce(lines, %{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [key, val] -> Map.put(acc, String.trim(key), String.trim(val))
            _ -> acc
          end
        end)

      %{
        secret_key_base: Map.get(map, "SECRET_KEY_BASE") || generate_secret_key_base(),
        cloak_key: Map.get(map, "CLOAK_KEY") || generate_cloak_key()
      }
    else
      secret_key_base = generate_secret_key_base()
      cloak_key = generate_cloak_key()

      payload = "SECRET_KEY_BASE=#{secret_key_base}\nCLOAK_KEY=#{cloak_key}\n"
      File.write!(secrets_path, payload)

      %{secret_key_base: secret_key_base, cloak_key: cloak_key}
    end
  end

  @doc """
  Executes pending Ecto migrations for repos configured on :rx_generator.
  """
  def run_migrations do
    Application.load(@app)

    repos = Application.get_env(@app, :ecto_repos, [RxGenerator.Repo])

    for repo <- repos do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn r ->
          Ecto.Migrator.run(r, :up, all: true)
          backfill_fts5_if_empty(r)
        end)
    end

    :ok
  end

  defp backfill_fts5_if_empty(repo) do
    with {:ok, %{rows: [[fts_count]]}} <-
           Ecto.Adapters.SQL.query(repo, "SELECT count(*) FROM drug_catalog_fts", []),
         {:ok, %{rows: [[cat_count]]}} <-
           Ecto.Adapters.SQL.query(repo, "SELECT count(*) FROM drug_catalog", []),
         true <- fts_count == 0 and cat_count > 0 do
      Ecto.Adapters.SQL.query!(
        repo,
        """
        INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
        SELECT rowid, brand_name, generic_name, strength, dosage_form FROM drug_catalog;
        """,
        []
      )
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp generate_secret_key_base do
    :crypto.strong_rand_bytes(64) |> Base.encode64()
  end

  defp generate_cloak_key do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end
end
