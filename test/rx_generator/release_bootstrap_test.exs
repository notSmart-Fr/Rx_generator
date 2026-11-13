defmodule RxGenerator.ReleaseBootstrapTest do
  use ExUnit.Case, async: false

  alias RxGenerator.Release

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "rx_generator_test_data_#{:erlang.unique_integer([:positive])}"
           )

  setup do
    File.rm_rf!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "resolves data directory based on target OS" do
    dir = Release.resolve_user_data_dir()
    assert is_binary(dir)
    assert String.length(dir) > 0
  end

  test "ensures user data directory and secrets file are created" do
    assert :ok = Release.ensure_user_data_dir(@tmp_dir)
    assert File.dir?(@tmp_dir)

    secrets = Release.ensure_secrets(@tmp_dir)
    assert is_binary(secrets.secret_key_base)
    assert is_binary(secrets.cloak_key)

    secrets_file = Path.join(@tmp_dir, "secrets.env")
    assert File.exists?(secrets_file)

    # Calling it again returns persistent secrets
    cached_secrets = Release.ensure_secrets(@tmp_dir)
    assert cached_secrets.secret_key_base == secrets.secret_key_base
    assert cached_secrets.cloak_key == secrets.cloak_key
  end

  test "ensures database file is provisioned from template" do
    template_path = Path.join(@tmp_dir, "template.db")
    File.mkdir_p!(@tmp_dir)
    File.write!(template_path, "SQLITE_HEADER_MOCK")

    dest_db = Path.join(@tmp_dir, "working.db")
    refute File.exists?(dest_db)

    assert :ok = Release.ensure_database_file(dest_db, template_path)
    assert File.exists?(dest_db)
    assert File.read!(dest_db) == "SQLITE_HEADER_MOCK"

    # Idempotent: does not overwrite if destination exists
    File.write!(dest_db, "MUTATED_WORKING_DATA")
    assert :ok = Release.ensure_database_file(dest_db, template_path)
    assert File.read!(dest_db) == "MUTATED_WORKING_DATA"
  end

  test "verifies full bootstrap lifecycle provisions actual seed database and runs migrations" do
    # Point user data directory to a clean temp sandbox
    prev_appdata = System.get_env("APPDATA")

    on_exit(fn ->
      if prev_appdata,
        do: System.put_env("APPDATA", prev_appdata),
        else: System.delete_env("APPDATA")

      System.delete_env("DATABASE_PATH")
      System.delete_env("SECRET_KEY_BASE")
      System.delete_env("CLOAK_KEY")
    end)

    sandbox_user_dir = Path.join(@tmp_dir, "appdata")
    System.put_env("APPDATA", sandbox_user_dir)

    # Clean any prior environment variables
    System.delete_env("DATABASE_PATH")
    System.delete_env("SECRET_KEY_BASE")
    System.delete_env("CLOAK_KEY")

    # In test environment, RxGenerator.Repo is in Sandbox mode.
    Ecto.Adapters.SQL.Sandbox.checkout(RxGenerator.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(RxGenerator.Repo, {:shared, self()})

    # Run full bootstrap sequence
    assert :ok = Release.bootstrap()

    # Verify directory created
    expected_data_dir = Release.resolve_user_data_dir()
    assert File.dir?(expected_data_dir)

    # Verify working db is populated and not empty
    working_db = Path.join(expected_data_dir, "rx_generator.db")
    assert File.exists?(working_db)
    assert File.stat!(working_db).size > 0

    # Verify secrets file is populated with valid keys
    secrets_file = Path.join(expected_data_dir, "secrets.env")
    assert File.exists?(secrets_file)
    assert is_binary(System.get_env("SECRET_KEY_BASE"))
    assert is_binary(System.get_env("CLOAK_KEY"))

    # Assert database is queryable via SQLite and formulary drugs exist
    {:ok, conn} = Exqlite.Sqlite3.open(working_db)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog;")
    {:row, [drug_count]} = Exqlite.Sqlite3.step(conn, stmt)
    assert drug_count > 0

    # Verify migrations table exists and is up to date
    {:ok, m_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM schema_migrations;")
    {:row, [migration_count]} = Exqlite.Sqlite3.step(conn, m_stmt)
    assert migration_count > 0

    # T024: Verify pre-indexed FTS5 trigram and 256-dim vector tables are populated
    {:ok, fts_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog_fts;")
    {:row, [fts_count]} = Exqlite.Sqlite3.step(conn, fts_stmt)
    assert fts_count >= 10, "Expected >= 10 FTS5 rows in bootstrapped DB, got #{fts_count}"

    {:ok, vec_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog_vectors;")
    {:row, [vec_count]} = Exqlite.Sqlite3.step(conn, vec_stmt)
    assert vec_count >= 10, "Expected >= 10 vector rows in bootstrapped DB, got #{vec_count}"

    Exqlite.Sqlite3.close(conn)

    System.delete_env("APPDATA")
    System.delete_env("DATABASE_PATH")
    System.delete_env("SECRET_KEY_BASE")
    System.delete_env("CLOAK_KEY")
  end

  test "T025: RxGenerator.Vault resolves persistent CLOAK_KEY from secrets.env" do
    Release.ensure_user_data_dir(@tmp_dir)
    secrets = Release.ensure_secrets(@tmp_dir)

    prev_cloak = System.get_env("CLOAK_KEY")

    on_exit(fn ->
      if prev_cloak,
        do: System.put_env("CLOAK_KEY", prev_cloak),
        else: System.delete_env("CLOAK_KEY")
    end)

    System.put_env("CLOAK_KEY", secrets.cloak_key)

    resolved_key = RxGenerator.Vault.resolve_vault_key([])
    expected_key = Base.decode64!(secrets.cloak_key)
    fallback_key = :crypto.hash(:sha256, "rx_generator_edge_vault_master_key_2026")

    assert byte_size(resolved_key) == 32
    assert resolved_key == expected_key
    assert resolved_key != fallback_key
  end
end
