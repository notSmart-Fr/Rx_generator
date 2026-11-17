defmodule RxGenerator.Prescriptions.BengaliTranslator do
  @moduledoc """
  Translates clinical dosage matrices, durations, and timing tokens
  into canonical colloquial Bengali per Article II and Bangladesh High Court directives.
  Canonical format: [Bengali Numerals Matrix] — [Timing] — [Duration]
  """

  @bengali_digits %{
    "0" => "০",
    "1" => "১",
    "2" => "২",
    "3" => "৩",
    "4" => "৪",
    "5" => "৫",
    "6" => "৬",
    "7" => "৭",
    "8" => "৮",
    "9" => "৯"
  }

  @timing_map %{
    :pc => "ভরা পেটে",
    "pc" => "ভরা পেটে",
    "after_meal" => "ভরা পেটে",
    "after meal" => "ভরা পেটে",
    :ac => "খাবার ৩০ মিনিট আগে",
    "ac" => "খাবার ৩০ মিনিট আগে",
    "before_meal" => "খাবার ৩০ মিনিট আগে",
    "before meal" => "খাবার ৩০ মিনিট আগে",
    :empty => "খালি পেটে",
    "empty" => "খালি পেটে",
    "empty_stomach" => "খালি পেটে",
    "empty stomach" => "খালি পেটে",
    :with_meal => "খাবারের সাথে",
    "with_meal" => "খাবারের সাথে",
    "with meal" => "খাবারের সাথে",
    :hs => "ঘুমানোর আগে",
    "hs" => "ঘুমানোর আগে",
    "at_bedtime" => "ঘুমানোর আগে",
    "bedtime" => "ঘুমানোর আগে",
    :sos => "প্রয়োজনে",
    "sos" => "প্রয়োজনে",
    :stat => "অবিলম্বে",
    "stat" => "অবিলম্বে"
  }

  @slot_labels_3 ["সকাল", "দুপুর", "রাত"]
  @slot_labels_4 ["সকাল", "দুপুর", "সন্ধ্যা", "রাত"]

  @doc """
  Generates the canonical single-line Bengali direction string:
  `[Bengali Numerals Matrix] — [Timing] — [Duration]`
  """
  def to_canonical(dosage_matrix, duration_expression, timing_instruction) do
    bengali_dosage = translate_dosage(dosage_matrix)
    bengali_timing = translate_timing(timing_instruction)
    bengali_duration = translate_duration(duration_expression)

    parts =
      [bengali_dosage, bengali_timing, bengali_duration]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " — ")
  end

  @doc """
  Generates the secondary colloquial breakdown line (e.g. `সকাল ১, দুপুর ০, রাত ১`).
  """
  def to_breakdown(matrix)
      when matrix in [:as_directed, "as_directed", "as directed", nil, ""],
      do: nil

  def to_breakdown(dosage_matrix) when is_binary(dosage_matrix) do
    if String.contains?(dosage_matrix, "+") do
      slots = String.split(dosage_matrix, "+")

      labels =
        case length(slots) do
          4 -> @slot_labels_4
          _ -> @slot_labels_3
        end

      slots
      |> Enum.zip(labels)
      |> Enum.map_join(", ", fn {val, label} ->
        bengali_val = to_bengali_numerals(val)
        "#{label} #{bengali_val}"
      end)
    else
      nil
    end
  end

  def to_breakdown(_), do: nil

  @doc """
  Translates a timing token atom or string (including optional `; custom note`) into Bengali.
  """
  def translate_timing(nil), do: nil

  def translate_timing(code) when is_atom(code) do
    Map.get(@timing_map, code)
  end

  def translate_timing(code) when is_binary(code) do
    case Map.get(@timing_map, code) do
      nil ->
        if String.contains?(code, ";") do
          [raw_timing, raw_note] = String.split(code, ";", parts: 2)
          base_timing = Map.get(@timing_map, String.trim(raw_timing))
          custom_note = raw_note |> String.trim() |> to_bengali_numerals()

          cond do
            base_timing && custom_note != "" -> "#{base_timing} (#{custom_note})"
            base_timing -> base_timing
            custom_note != "" -> custom_note
            true -> nil
          end
        else
          nil
        end

      translated ->
        translated
    end
  end

  @doc """
  Translates duration strings or atoms into Bengali.
  """
  def translate_duration(nil), do: nil
  def translate_duration(:as_needed), do: "প্রয়োজনমতো"
  def translate_duration("as_needed"), do: "প্রয়োজনমতো"
  def translate_duration("as needed"), do: "প্রয়োজনমতো"
  def translate_duration(:continue), do: "চলবে"
  def translate_duration("continue"), do: "চলবে"
  def translate_duration("cont"), do: "চলবে"

  def translate_duration(expr) when is_binary(expr) do
    trimmed = String.trim(expr)
    lower = String.downcase(trimmed)

    cond do
      lower in ["as needed", "as_needed", ":as_needed"] ->
        "প্রয়োজনমতো"

      lower in ["continue", "cont", ":continue"] ->
        "চলবে"

      Regex.match?(~r/^(\d+)\s*d(?:ays?)?$/i, trimmed) ->
        [_, num] = Regex.run(~r/^(\d+)\s*d(?:ays?)?$/i, trimmed)
        "#{to_bengali_numerals(num)} দিন"

      Regex.match?(~r/^(\d+)\s*weeks?$/i, trimmed) ->
        [_, num] = Regex.run(~r/^(\d+)\s*weeks?$/i, trimmed)
        "#{to_bengali_numerals(num)} সপ্তাহ"

      Regex.match?(~r/^(\d+)\s*months?$/i, trimmed) ->
        [_, num] = Regex.run(~r/^(\d+)\s*months?$/i, trimmed)
        "#{to_bengali_numerals(num)} মাস"

      true ->
        to_bengali_numerals(trimmed)
    end
  end

  @doc """
  Translates a dosage matrix into Bengali numerals.
  """
  def translate_dosage(nil), do: nil
  def translate_dosage(:as_directed), do: "চিকিৎসকের পরামর্শ অনুযায়ী"
  def translate_dosage("as_directed"), do: "চিকিৎসকের পরামর্শ অনুযায়ী"
  def translate_dosage("as directed"), do: "চিকিৎসকের পরামর্শ অনুযায়ী"
  def translate_dosage(dose) when dose in [:sos, "sos", "SOS"], do: "প্রয়োজনে"
  def translate_dosage(dose) when dose in ["1 tsp", "1tsp"], do: "১ চামচ"
  def translate_dosage(dose) when dose in ["as needed", "as_needed"], do: "প্রয়োজনমতো"

  def translate_dosage(matrix) when is_binary(matrix) do
    cond do
      match = Regex.run(~r/^(\d+)\s*drops?$/i, String.trim(matrix)) ->
        [_, num] = match
        "#{to_bengali_numerals(num)} ফোঁটা"

      match = Regex.run(~r/^(\d+)\s*puffs?$/i, String.trim(matrix)) ->
        [_, num] = match
        "#{to_bengali_numerals(num)} পাফ"

      true ->
        to_bengali_numerals(matrix)
    end
  end

  def translate_dosage(_), do: nil

  @doc """
  Replaces all ASCII digits 0-9 with Bengali digits ০-৯.
  """
  def to_bengali_numerals(str) when is_binary(str) do
    String.replace(str, ~r/[0-9]/, fn digit ->
      Map.get(@bengali_digits, digit, digit)
    end)
  end

  def to_bengali_numerals(other), do: to_string(other)
end
