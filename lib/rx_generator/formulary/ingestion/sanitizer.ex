defmodule RxGenerator.Formulary.Ingestion.Sanitizer do
  @moduledoc """
  Sanitizes raw medicine catalog records exported from the DGDA database.

  Responsibilities:
  1. Filters out bulk industrial manufacturing chemicals (Kg, Liter, Drum, Bulk, raw Gm).
  2. Splits compound "Generic Name With Strength" strings into clean, normalized
     `generic_name` and `strength` attributes using precompiled regexes.
  3. Evaluates scheduled controlled substances under the Bangladesh Narcotics Control Act 2018.
  4. Normalizes dosage forms into canonical title case.
  5. Safely handles products lacking explicit numerical strength (e.g., ORS).
  """

  alias RxGenerator.Formulary.Ingestion.ControlledDrugs

  # Bulk packaging dosage form patterns that represent industrial raw chemicals rather than finished formulations
  @bulk_keywords ~r/\b(kg|liter|litre|drum|bulk|ton)\b/i
  @raw_gm_pattern ~r/\bgm\s*\(raw\)/i

  # Precompiled regex for a single molecule-strength pair:
  # Matches e.g. "Amoxicillin 500 mg", "Lidocaine Hydrochloride 10 mg/ml", "Paracetamol 120 mg/5 ml"
  # Notice \d* after the slash to allow both "/ml" and "/5 ml"
  @pair_regex ~r/^([^\d]+?)\s+(\d+(?:\.\d+)?\s*(?:mg|gm|g|ml|mcg|iu|%|w\/v|w\/w|v\/v)(?:\s*\/\s*\d*(?:\.\d+)?\s*(?:ml|mg|g|gm))?)$/i

  # Precompiled regex for trailing combinations:
  # Matches generic names with multiple trailing strengths, e.g.
  # "Isoniazid + Rifampicin 75 mg + 150 mg"
  # "Ethambutol + Isoniazid + Rifampicin 275 mg + 75 mg + 150 mg"
  # "Lidocaine Hydrochloride 10 mg/ml"
  @trailing_regex ~r/^(.*?)\s+((?:\d+(?:\.\d+)?\s*(?:mg|gm|g|ml|mcg|iu|%|w\/v|w\/w|v\/v)(?:\s*\/\s*\d*(?:\.\d+)?\s*(?:ml|mg|g|gm))?(?:\s*[\+&]\s*|\s+and\s+)?)+)$/i

  @doc """
  Sanitizes a raw CSV row map.
  Returns `{:ok, item_map}` or `:skip` if the record represents non-prescribable bulk chemical.
  """
  @spec sanitize_record(map()) :: {:ok, map()} | :skip
  def sanitize_record(row) when is_map(row) do
    dosage_form = get_field(row, ["Dosage Form", :dosage_form, "dosage_form"])

    if bulk_unit?(dosage_form) do
      :skip
    else
      brand_name = get_field(row, ["Trade Name", :brand_name, "brand_name"]) || ""

      raw_generic =
        get_field(row, [
          "Generic Name With Strength",
          :generic_name_with_strength,
          "generic_name_with_strength"
        ]) || ""

      manufacturer = get_field(row, ["Company", :manufacturer, "manufacturer"]) || ""
      dgda_reg_no = get_field(row, ["DAR No", :dgda_reg_no, "dgda_reg_no"])

      {generic_name, strength} = split_generic_and_strength(raw_generic)
      is_controlled = ControlledDrugs.controlled?(generic_name)

      {:ok,
       %{
         brand_name: clean_text(brand_name),
         generic_name: clean_text(generic_name),
         strength: clean_text(strength),
         dosage_form: canonicalize_dosage_form(dosage_form),
         manufacturer: clean_text(manufacturer),
         dgda_reg_no: if(dgda_reg_no, do: clean_text(dgda_reg_no)),
         is_controlled: is_controlled
       }}
    end
  end

  @doc """
  Determines if a dosage form string represents bulk industrial chemical packaging.
  """
  @spec bulk_unit?(String.t() | nil) :: boolean()
  def bulk_unit?(nil), do: false

  def bulk_unit?(dosage_form) when is_binary(dosage_form) do
    normalized = String.trim(dosage_form)
    Regex.match?(@bulk_keywords, normalized) or Regex.match?(@raw_gm_pattern, normalized)
  end

  @doc """
  Splits a "Generic Name With Strength" string into `{generic_name, strength}`.
  Handles:
  - Interspersed FDCs: "Amoxicillin 500 mg + Clavulanic Acid 125 mg"
  - Conjunctions with `&` or `+`: "Paracetamol 500 mg & Caffeine 65 mg"
  - Liquid / fractional units: "10 mg/ml", "120 mg/5 ml"
  - Trailing combinations: "Isoniazid + Rifampicin 75 mg + 150 mg"
  - Single molecules: "Omeprazole 20 mg"
  - Zero-strength formulations: "Oral Rehydration Salt" -> {"Oral Rehydration Salt", "As formulated"}
  """
  @spec split_generic_and_strength(String.t()) :: {String.t(), String.t()}
  def split_generic_and_strength(""), do: {"", "As formulated"}

  def split_generic_and_strength(raw_text) when is_binary(raw_text) do
    cleaned = clean_text(raw_text)

    # Strategy 1: Check for interspersed FDC format where every part has its own strength
    case try_parse_interspersed(cleaned) do
      {:ok, generic_name, strength} ->
        {generic_name, strength}

      :error ->
        # Strategy 2: Check for trailing combination or single molecule format
        case Regex.run(@trailing_regex, cleaned) do
          [_, generic_part, strength_part] ->
            {clean_text(generic_part), clean_text(strength_part)}

          _ ->
            # Fallback for formulations without explicit numerical strength (e.g. Oral Rehydration Salt)
            {cleaned, "As formulated"}
        end
    end
  end

  defp try_parse_interspersed(text) do
    parts = String.split(text, ~r/\s*[\+&]\s*|\s+and\s+/i, trim: true)

    # Only treat as interspersed if there are multiple parts and every part has a valid molecule + strength
    if length(parts) > 1 do
      results =
        Enum.map(parts, fn part ->
          case Regex.run(@pair_regex, part) do
            [_, molecule, strength] ->
              trimmed_molecule = clean_text(molecule)
              # Molecule must not be empty and must start with letters
              if String.length(trimmed_molecule) > 0 and
                   not Regex.match?(~r/^\d/, trimmed_molecule) do
                {:ok, trimmed_molecule, clean_text(strength)}
              else
                :error
              end

            _ ->
              :error
          end
        end)

      if Enum.all?(results, &match?({:ok, _, _}, &1)) do
        generics = Enum.map(results, fn {:ok, g, _} -> g end) |> Enum.join(" + ")
        strengths = Enum.map(results, fn {:ok, _, s} -> s end) |> Enum.join(" + ")
        {:ok, generics, strengths}
      else
        :error
      end
    else
      :error
    end
  end

  @doc """
  Normalizes messy dosage form strings into canonical title-case format.
  e.g. " capsule " -> "Capsule", "TABLET" -> "Tablet", "oral suspension" -> "Oral Suspension"
  """
  @spec canonicalize_dosage_form(String.t() | nil) :: String.t()
  def canonicalize_dosage_form(nil), do: ""

  def canonicalize_dosage_form(dosage_form) when is_binary(dosage_form) do
    dosage_form
    |> clean_text()
    |> String.split(" ", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_field(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, val} when is_binary(val) -> val
        _ -> nil
      end
    end)
  end

  defp clean_text(nil), do: ""

  defp clean_text(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
end
