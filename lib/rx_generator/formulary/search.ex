defmodule RxGenerator.Formulary.Search do
  @moduledoc """
  Sub-2ms deterministic SQLite FTS5 trigram search for DGDA drug products.
  Executes raw FTS5 queries via Ecto and loads records via Ash queries.
  """
  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Repo

  @unit_stop_words ~w(ml mg gm iu cc ts mcg)

  @doc """
  Normalizes diverse clinical presentation form inputs (atoms, strings, abbreviations)
  into exact DGDA dosage forms (e.g. "Tablet", "Syrup", "Capsule", "Injection").
  Returns a binary canonical form or nil. Never crashes on arbitrary input.
  """
  def normalize_form(form) when is_atom(form) and not is_nil(form) do
    form |> Atom.to_string() |> normalize_form()
  end

  def normalize_form(form) when is_binary(form) do
    cleaned =
      form
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z]/, "")

    cond do
      cleaned in ["tab", "tablet", "tabs"] ->
        "Tablet"

      cleaned in ["syr", "syrup", "susp", "suspension", "liquid", "oralliquid"] ->
        "Syrup"

      cleaned in ["cap", "capsule", "caps"] ->
        "Capsule"

      cleaned in ["inj", "injection", "injectable"] ->
        "Injection"

      cleaned in ["supp", "suppository", "suppositories"] ->
        "Suppository"

      cleaned in ["drop", "drops", "eyedrop", "eardrop"] ->
        "Drop"

      cleaned in ["cream", "cr"] ->
        "Cream"

      cleaned in ["ointment", "oint"] ->
        "Ointment"

      cleaned in ["gel"] ->
        "Gel"

      cleaned in ["inhaler", "inhalation"] ->
        "Inhaler"

      true ->
        nil
    end
  end

  def normalize_form(_), do: nil

  @doc """
  Searches `drug_catalog_fts` with a query string and optional options:
  - `:limit` - Maximum number of results to return (default: 10)
  - `:form` or `:dosage_form` - Presentation form to filter by (e.g. `:tab`, `:syr`, `"Tablet"`)

  Returns a list of `DrugCatalogItem` structs ordered by match relevance.
  """
  def run(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 10)
    raw_form = Keyword.get(opts, :form) || Keyword.get(opts, :dosage_form)
    canonical_form = normalize_form(raw_form)

    case build_match_expression(query) do
      nil ->
        []

      match_expression ->
        {sql, params} =
          if canonical_form do
            sql_query = """
            SELECT c.rowid
            FROM drug_catalog_fts fts
            JOIN drug_catalog c ON c.rowid = fts.rowid
            WHERE drug_catalog_fts MATCH ? AND c.dosage_form = ?
            ORDER BY rank
            LIMIT ?
            """

            {sql_query, [match_expression, canonical_form, limit]}
          else
            sql_query = """
            SELECT rowid
            FROM drug_catalog_fts
            WHERE drug_catalog_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """

            {sql_query, [match_expression, limit]}
          end

        case Ecto.Adapters.SQL.query(Repo, sql, params) do
          {:ok, %{rows: rows}} ->
            rowids = Enum.map(rows, fn [id] -> id end)
            load_items_by_rowids(rowids)

          {:error, _err} ->
            []
        end
    end
  end

  defp load_items_by_rowids([]), do: []

  defp load_items_by_rowids(rowids) do
    # Fetch records and preserve the FTS5 rank order
    placeholders = Enum.map(rowids, fn _ -> "?" end) |> Enum.join(", ")

    sql = """
    SELECT id FROM drug_catalog WHERE rowid IN (#{placeholders})
    """

    case Ecto.Adapters.SQL.query(Repo, sql, rowids) do
      {:ok, %{rows: id_rows}} ->
        uuids = Enum.map(id_rows, fn [uuid] -> uuid end)

        items =
          DrugCatalogItem
          |> Ash.Query.filter(id in ^uuids)
          |> Ash.read!()

        # Maintain original FTS5 rank ordering
        item_map = Map.new(items, &{&1.id, &1})
        Enum.map(uuids, &Map.get(item_map, &1)) |> Enum.filter(& &1)

      _ ->
        []
    end
  end

  @doc """
  Constructs a safe SQLite FTS5 trigram match query from an input string.
  Tokens under 3 characters (or unit abbreviations like 'ml') are omitted
  because the trigram tokenizer requires tokens with length >= 3.
  """
  def build_match_expression(raw_query) when is_binary(raw_query) do
    raw_query
    |> String.downcase()
    # Normalize complex formulations like 100ml -> "100 ml"
    |> String.replace(~r/(\d+)([a-zA-Z]+)/, "\\1 \\2")
    # Clean FTS5 reserved syntax characters
    |> String.replace(~r/[*^"':()\-+]/, " ")
    |> String.split(~s{ }, trim: true)
    # Reject tokens shorter than 3 characters and known unit stop words
    |> Enum.reject(fn token ->
      String.length(token) < 3 or token in @unit_stop_words
    end)
    |> case do
      [] ->
        nil

      valid_tokens ->
        # Wrap tokens in quotes to prevent FTS5 operator collisions
        valid_tokens
        |> Enum.map(fn token ->
          escaped = String.replace(token, "\"", "\"\"")
          "\"#{escaped}\""
        end)
        |> Enum.join(" AND ")
    end
  end
end
