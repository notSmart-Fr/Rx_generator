defmodule Mix.Tasks.Formulary.Vectorize do
  @moduledoc """
  Pre-computes and persists 256-D normalized embeddings for all prescribable DGDA catalog items.

  ## Options

    * `--batch-size` - Number of items to process in a batch (default: 64)
    * `--force` - Re-compute and overwrite existing vectors
    * `--quiet` - Suppress progress log output

  ## Examples

      mix formulary.vectorize
      mix formulary.vectorize --batch-size 32 --force
  """
  use Mix.Task

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.DrugCatalogVector
  alias RxGenerator.Formulary.Ingestion.Vectorizer
  alias RxGenerator.Repo
  import Ecto.Query

  @shortdoc "Pre-computes and persists 256-D normalized embeddings into drug_catalog_vectors"

  @impl Mix.Task
  def run(args) do
    # Ensure application is started
    Mix.Task.run("app.start")

    {opts, _argv, _errors} =
      OptionParser.parse(args,
        switches: [batch_size: :integer, force: :boolean, quiet: :boolean],
        aliases: [b: :batch_size, f: :force, q: :quiet]
      )

    batch_size = Keyword.get(opts, :batch_size, 64)
    force? = Keyword.get(opts, :force, false)
    quiet? = Keyword.get(opts, :quiet, false)

    log(
      quiet?,
      "Starting DGDA catalog vectorization (batch_size: #{batch_size}, force: #{force?})..."
    )

    # Fetch candidate items
    query =
      if force? do
        from(d in DrugCatalogItem, order_by: d.id)
      else
        from(d in DrugCatalogItem,
          left_join: v in DrugCatalogVector,
          on: v.drug_catalog_item_id == d.id,
          where: is_nil(v.id),
          order_by: d.id
        )
      end

    total_items = Repo.aggregate(query, :count, :id)
    log(quiet?, "Found #{total_items} item(s) to vectorize.")

    if total_items > 0 do
      process_in_batches(query, batch_size, quiet?)
    end

    log(quiet?, "Catalog vectorization completed successfully.")
    :ok
  end

  defp process_in_batches(query, batch_size, quiet?) do
    Repo.transaction(
      fn ->
        query
        |> Repo.stream(max_rows: batch_size)
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce(0, fn batch, acc ->
          texts = Enum.map(batch, &Vectorizer.format_canonical/1)
          {:ok, vectors} = Vectorizer.vectorize_batch(texts)

          now = DateTime.utc_now()

          upsert_entries =
            Enum.zip(batch, vectors)
            |> Enum.map(fn {item, vec} ->
              %{
                id: Ash.UUID.generate(),
                drug_catalog_item_id: item.id,
                embedding: vec,
                dimension: 256,
                model_version: "embedding_gemma_2_270m_mrl256",
                inserted_at: now,
                updated_at: now
              }
            end)

          Repo.insert_all(
            DrugCatalogVector,
            upsert_entries,
            on_conflict: {:replace, [:embedding, :dimension, :model_version, :updated_at]},
            conflict_target: :drug_catalog_item_id
          )

          processed = acc + length(batch)
          log(quiet?, "Vectorized #{processed} items...")
          processed
        end)
      end,
      timeout: :infinity
    )
  end

  defp log(true, _msg), do: :ok
  defp log(false, msg), do: Mix.shell().info("  [formulary.vectorize] #{msg}")
end
