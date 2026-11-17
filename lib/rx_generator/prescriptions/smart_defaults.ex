defmodule RxGenerator.Prescriptions.SmartDefaults do
  @moduledoc """
  Offline clinical intelligence helpers for smart Sig defaults, bounded clinical presets,
  encrypted clinical note/advice encoding, and real-time active generic ingredient guardrails.
  """

  @advice_delimiter "\n===ADVICE===\n"

  @doc """
  Bounded one-tap dose presets for right-column Rx cards.
  """
  def dose_presets, do: ["1+0+1", "1+1+1", "1+0+0", "0+0+1", "1 tsp", "SOS"]

  @doc """
  Bounded one-tap timing presets for right-column Rx cards.
  """
  def timing_presets do
    [
      {"pc", "After meal"},
      {"ac", "30 mins before meal"},
      {"empty", "Empty stomach"},
      {"hs", "Bedtime"}
    ]
  end

  @doc """
  Bounded one-tap duration presets for right-column Rx cards.
  """
  def duration_presets do
    [
      {"3 days", "3d"},
      {"5 days", "5d"},
      {"7 days", "7d"},
      {"14 days", "14d"},
      {"30 days", "30d"},
      {"continue", "Continue"}
    ]
  end

  @doc """
  Quick section prefixes for the optional 1/3 left clinical margin.
  """
  def clinical_prefixes, do: ["C/C", "O/E", "Dx", "Ix"]

  @doc """
  Curated one-tap Bengali advice chips for the General Advice footer.
  """
  def advice_chips do
    [
      "পর্যাপ্ত পানি পান করবেন",
      "নিয়মিত ওষুধ সেবন করবেন",
      "ঠান্ডা ও ধুলাবালি এড়িয়ে চলুন",
      "৭ দিন পর দেখা করবেন",
      "জ্বর ১০১° ফারেনহাইটের বেশি হলে প্যারাসিটামল খাবেন"
    ]
  end

  @doc """
  Splits encrypted `:clinical_notes` into `{left_margin_notes, general_advice}`.
  """
  def split_clinical_notes_and_advice(nil), do: {"", ""}

  def split_clinical_notes_and_advice(str) when is_binary(str) do
    case String.split(str, @advice_delimiter, parts: 2) do
      [notes, advice] -> {notes, advice}
      [notes] -> {notes, ""}
    end
  end

  @doc """
  Combines left-margin clinical notes and general advice for storage inside `:clinical_notes`.
  Preserves plain notes without delimiter when general advice is empty.
  """
  def combine_clinical_notes_and_advice(notes, advice) do
    clean_notes = notes || ""
    clean_advice = String.trim(advice || "")

    if clean_advice == "" do
      clean_notes
    else
      "#{clean_notes}#{@advice_delimiter}#{clean_advice}"
    end
  end

  @doc """
  Appends a clinical section prefix (`C/C:`, `O/E:`, `Dx:`, `Ix:`) if not already present.
  """
  def append_prefix(current_notes, prefix) do
    notes = to_string(current_notes || "")
    header = "#{prefix}:"

    if String.contains?(notes, header) do
      notes
    else
      trimmed = String.trim_trailing(notes)
      if trimmed == "", do: "#{header} ", else: "#{trimmed}\n#{header} "
    end
  end

  @doc """
  Toggles a Bengali advice line in the General Advice text.
  """
  def toggle_advice_line(current_advice, chip) do
    lines =
      (current_advice || "")
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if chip in lines do
      lines |> Enum.reject(&(&1 == chip)) |> Enum.join("\n")
    else
      (lines ++ [chip]) |> Enum.join("\n")
    end
  end

  @doc """
  Recommends clinically standard dosage, duration, and timing for a DGDA drug item
  based on its generic name and dosage form.
  """
  def for_drug(%{generic_name: generic, dosage_form: form}) do
    g = String.downcase(generic || "")
    f = String.downcase(form || "")

    cond do
      String.contains?(g, [
        "esomeprazole",
        "omeprazole",
        "pantoprazole",
        "rabeprazole",
        "lansoprazole"
      ]) ->
        %{
          dosage_matrix: "1+0+1",
          duration_expression: "14 days",
          timing_code: "ac",
          rationale: "PPI standard pre-meal regimen"
        }

      String.contains?(g, "azithromycin") ->
        %{
          dosage_matrix: "1+0+0",
          duration_expression: "3 days",
          timing_code: "pc",
          rationale: "Once-daily macrolide course"
        }

      String.contains?(g, [
        "ciprofloxacin",
        "amoxicillin",
        "cefuroxime",
        "cefixime",
        "flucloxacillin"
      ]) ->
        %{
          dosage_matrix: "1+0+1",
          duration_expression: "7 days",
          timing_code: "pc",
          rationale: "Standard antimicrobial course"
        }

      String.contains?(g, ["clonazepam", "diazepam", "alprazolam", "bromazepam"]) ->
        %{
          dosage_matrix: "0+0+1",
          duration_expression: "7 days",
          timing_code: "hs",
          rationale: "Bedtime sedative/anxiolytic regimen"
        }

      String.contains?(g, [
        "ketotifen",
        "montelukast",
        "cetirizine",
        "fexofenadine",
        "levocetirizine"
      ]) ->
        if f == "syrup" do
          %{
            dosage_matrix: "1 tsp",
            duration_expression: "7 days",
            timing_code: "pc",
            rationale: "Liquid oral maintenance"
          }
        else
          %{
            dosage_matrix: "0+0+1",
            duration_expression: "14 days",
            timing_code: "pc",
            rationale: "Evening allergy/prophylaxis regimen"
          }
        end

      String.contains?(g, ["paracetamol", "aceclofenac", "naproxen", "ibuprofen"]) ->
        %{
          dosage_matrix: "1+0+1",
          duration_expression: "3 days",
          timing_code: "pc",
          rationale: "Post-meal analgesic/antipyretic regimen"
        }

      f == "syrup" ->
        %{
          dosage_matrix: "1 tsp",
          duration_expression: "5 days",
          timing_code: "pc",
          rationale: "Standard liquid regimen"
        }

      f == "drop" ->
        %{
          dosage_matrix: "2 drops",
          duration_expression: "5 days",
          timing_code: nil,
          rationale: "Standard drops regimen"
        }

      f == "inhaler" ->
        %{
          dosage_matrix: "2 puffs",
          duration_expression: "as needed",
          timing_code: "sos",
          rationale: "Inhaler relief regimen"
        }

      true ->
        %{
          dosage_matrix: "1+0+1",
          duration_expression: "5 days",
          timing_code: "pc",
          rationale: "Standard adult oral regimen"
        }
    end
  end

  def for_drug(_),
    do: %{
      dosage_matrix: "1+0+1",
      duration_expression: "5 days",
      timing_code: "pc",
      rationale: "Standard adult oral regimen"
    }

  @doc """
  Splits a `timing_instruction` string into `{timing_code_or_nil, custom_note}`.
  """
  def split_timing_and_note(nil), do: {nil, ""}

  def split_timing_and_note(str) when is_binary(str) do
    if String.contains?(str, ";") do
      [raw_timing, raw_note] = String.split(str, ";", parts: 2)
      timing = String.trim(raw_timing)
      {if(timing == "", do: nil, else: timing), String.trim(raw_note)}
    else
      trimmed = String.trim(str)
      {if(trimmed == "", do: nil, else: trimmed), ""}
    end
  end

  def split_timing_and_note(other), do: {to_string(other), ""}

  @doc """
  Combines a timing code and optional custom note into a single stored string.
  """
  def combine_timing_and_note(timing_code, custom_note) do
    t = timing_code && String.trim(to_string(timing_code))
    n = custom_note && String.trim(to_string(custom_note))

    t_val = if(t in [nil, ""], do: nil, else: t)
    n_val = if(n in [nil, ""], do: nil, else: n)

    cond do
      t_val && n_val -> "#{t_val}; #{n_val}"
      t_val -> t_val
      n_val -> "; #{n_val}"
      true -> nil
    end
  end

  @doc """
  Detects clinical safety warnings across active prescription items:
  - Duplicate active generic ingredients (e.g. Paracetamol in Napa + Napa Extra)
  - Controlled substance alerts
  """
  def detect_warnings(items) when is_list(items) do
    active = Enum.filter(items, &is_nil(Map.get(&1, :archived_at)))

    duplicate_warnings =
      active
      |> Enum.flat_map(fn item ->
        item.generic_name_snapshot
        |> to_string()
        |> String.split(~r/[+\/,]/, trim: true)
        |> Enum.map(fn ing -> {String.upcase(String.trim(ing)), item.brand_name_snapshot} end)
        |> Enum.reject(fn {ing, _} -> ing == "" end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_ing, brands} -> length(brands) > 1 end)
      |> Enum.map(fn {ingredient, brands} ->
        unique_brands = Enum.uniq(brands)

        %{
          kind: :duplicate_generic,
          ingredient: ingredient,
          brands: unique_brands,
          message:
            "Therapeutic overlap: #{ingredient} is present in multiple prescribed drugs (#{Enum.join(unique_brands, ", ")})."
        }
      end)

    controlled_brands =
      active
      |> Enum.filter(&(&1.is_controlled_snapshot == true))
      |> Enum.map(& &1.brand_name_snapshot)
      |> Enum.uniq()

    controlled_warnings =
      if controlled_brands != [] do
        [
          %{
            kind: :controlled_substance,
            brands: controlled_brands,
            message:
              "Controlled substance prescribed (#{Enum.join(controlled_brands, ", ")}) — verify BM&DC schedule compliance."
          }
        ]
      else
        []
      end

    duplicate_warnings ++ controlled_warnings
  end

  def detect_warnings(_), do: []
end
