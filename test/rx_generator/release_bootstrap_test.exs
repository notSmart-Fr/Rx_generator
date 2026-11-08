defmodule RxGenerator.ReleaseBootstrapTest do
  use ExUnit.Case, async: false

  alias RxGenerator.Release

  @tmp_dir Path.join(System.tmp_dir!(), "rx_generator_test_data_#{:erlang.unique_integer([:positive])}")

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

    Exqlite.Sqlite3.close(conn)
  end
end

