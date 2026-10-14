defmodule RxGenerator.Formulary.Ingestion do
  @moduledoc """
  High-performance streaming ingestion pipeline for the DGDA drug catalog.
  Processes large CSV exports in configurable chunks, sanitizes records,
  filters out bulk raw manufacturing chemicals, flags scheduled controlled substances,
  and synchronizes SQLite FTS5 via atomic rebuild.
  """

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.Ingestion.Sanitizer
  alias RxGenerator.Repo

  NimbleCSV.define(DGDAParser, trim_cells: true)

  @default_file_path "priv/data/medicine_information_export.csv"
  @default_chunk_size 500

  @doc "Convenience alias for `ingest_csv/2`."
  def run(opts \\ [])
  def run(opts) when is_list(opts), do: ingest_csv(@default_file_path, opts)
  def run(file_path) when is_binary(file_path), do: ingest_csv(file_path, [])
  def run(file_path, opts), do: ingest_csv(file_path, opts)

  @doc """
  Streams a DGDA CSV file, sanitizes rows, filters bulk units, flags controlled substances,
  and persists DrugCatalogItem records in chunks.

  Options:
    * `:chunk_size` - integer, default: 500
    * `:rebuild_fts?` - boolean, default: true
  """
  @spec ingest_csv(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def ingest_csv(file_path \\ @default_file_path, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    rebuild_fts? = Keyword.get(opts, :rebuild_fts?, true)

    if File.exists?(file_path) do
      try do
        # 1. Drop SQLite triggers to avoid shadow table locks and slow row-by-row updates during bulk ingest
        drop_triggers()

        # 2. Process stream in chunks
        stats =
          file_path
          |> File.stream!()
          |> Stream.map(&preprocess_line/1)
          |> DGDAParser.parse_stream(skip_headers: false)
          |> Stream.transform(
            fn -> nil end,
            fn row, headers ->
              if headers == nil do
                # First line is headers
                cleaned_headers = Enum.map(row, &clean_header/1)
                {[], cleaned_headers}
              else
                # Data row
                row_map = Enum.zip(headers, row) |> Map.new()
                {[row_map], headers}
              end
            end,
            fn _headers -> :ok end
          )
          |> Stream.chunk_every(chunk_size)
          |> Enum.reduce(%{inserted: 0, excluded_bulk: 0, controlled: 0}, fn chunk, acc ->
            process_chunk(chunk, acc)
          end)

        # 3. Restore triggers and rebuild FTS5 index atomically
        restore_triggers()

        if rebuild_fts? do
          rebuild_fts()
        end

        {:ok, stats}
      rescue
        error ->
          # Ensure triggers are restored even on failure
          restore_triggers()
          reraise error, __STACKTRACE__
      end
    else
      {:error, {:file_not_found, file_path}}
    end
  end

  defp preprocess_line(line) do
    # Remove leading/trailing spaces around delimiters so quoted cells parse properly
    line
    |> String.replace(~r/,\s*"/, ",\"")
    |> String.replace(~r/"\s*,/, "\",")
    |> String.trim_leading()
  end

  defp clean_header(header) do
    header
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp process_chunk(chunk, acc) do
    now = DateTime.utc_now()

    {items_to_insert, chunk_excluded, chunk_controlled} =
      Enum.reduce(chunk, {[], 0, 0}, fn row, {items, excluded, controlled} ->
        case Sanitizer.sanitize_record(row) do
          {:ok, item} ->
            db_item = %{
              id: Ash.UUID.generate(),
              brand_name: item.brand_name,
              generic_name: item.generic_name,
              strength: item.strength,
              dosage_form: item.dosage_form,
              manufacturer: item.manufacturer,
              dgda_reg_no: item.dgda_reg_no,
              is_controlled: item.is_controlled,
              inserted_at: now,
              updated_at: now
            }

            ctrl_inc = if item.is_controlled, do: 1, else: 0
            {[db_item | items], excluded, controlled + ctrl_inc}

          :skip ->
            {items, excluded + 1, controlled}
        end
      end)

    if items_to_insert != [] do
      # Bulk insert chunk with conflict target matching unique index
      {inserted_count, _} =
        Repo.insert_all(
          DrugCatalogItem,
          items_to_insert,
          on_conflict: :nothing,
          conflict_target: [:brand_name, :strength, :dosage_form]
        )

      %{
        acc
        | inserted: acc.inserted + inserted_count,
          excluded_bulk: acc.excluded_bulk + chunk_excluded,
          controlled: acc.controlled + chunk_controlled
      }
    else
      %{
        acc
        | excluded_bulk: acc.excluded_bulk + chunk_excluded,
          controlled: acc.controlled + chunk_controlled
      }
    end
  end

  defp drop_triggers do
    Repo.query("DROP TRIGGER IF EXISTS drug_catalog_ai")
    Repo.query("DROP TRIGGER IF EXISTS drug_catalog_ad")
    Repo.query("DROP TRIGGER IF EXISTS drug_catalog_au")
    :ok
  end

  defp restore_triggers do
    Repo.query("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ai AFTER INSERT ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    Repo.query("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_ad AFTER DELETE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
    END;
    """)

    Repo.query("""
    CREATE TRIGGER IF NOT EXISTS drug_catalog_au AFTER UPDATE ON drug_catalog BEGIN
      INSERT INTO drug_catalog_fts(drug_catalog_fts, rowid, brand_name, generic_name, strength, dosage_form)
      VALUES ('delete', old.rowid, old.brand_name, old.generic_name, old.strength, old.dosage_form);
      INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
      VALUES (new.rowid, new.brand_name, new.generic_name, new.strength, new.dosage_form);
    END;
    """)

    :ok
  end

  defp rebuild_fts do
    Repo.query!("""
    INSERT INTO drug_catalog_fts(rowid, brand_name, generic_name, strength, dosage_form)
    SELECT rowid, brand_name, generic_name, strength, dosage_form
    FROM drug_catalog
    WHERE rowid NOT IN (SELECT rowid FROM drug_catalog_fts);
    """)

    Repo.query("INSERT INTO drug_catalog_fts(drug_catalog_fts) VALUES('rebuild')")
    :ok
  end
end
