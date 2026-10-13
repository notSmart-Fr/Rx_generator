defmodule RxGenerator.Prescriptions.ShorthandParser do
  @moduledoc """
  Pure Elixir deterministic right-to-left DFA / token stream parser for clinical shorthand.
  Isolates timing, duration, and frequency matrices while protecting strength units.
  """
  alias RxGenerator.Prescriptions.ParsedShorthand

  @timing_tokens %{
    "pc" => :pc,
    "ac" => :ac,
    "hs" => :hs,
    "sos" => :sos,
    "stat" => :stat,
    "tds" => :tds,
    "tid" => :tds,
    "bd" => :bd,
    "bid" => :bd,
    "od" => :od,
    "qid" => :qid,
    "after meal" => :pc,
    "before meal" => :ac,
    "bedtime" => :hs
  }

  @form_prefixes %{
    "tab" => :tablet,
    "tablet" => :tablet,
    "cap" => :capsule,
    "capsule" => :capsule,
    "syr" => :syrup,
    "syrup" => :syrup,
    "inj" => :injection,
    "injection" => :injection,
    "drop" => :drops,
    "drops" => :drops,
    "supp" => :suppository,
    "oint" => :ointment
  }

  @doc """
  Parses a raw shorthand string (e.g. "napa xtra 1+0+1 5d pc") into a %ParsedShorthand{} or nil if empty.
  """
  def parse(raw_input) when is_binary(raw_input) do
    trimmed = String.trim(raw_input)

    if trimmed == "" do
      nil
    else
      tokens = String.split(trimmed, ~r/\s+/, trim: true)

      # 1. Extract dosage form prefix from beginning if present (e.g., "syrup tofen ...")
      {form_hint, tokens_after_form} = extract_form_prefix(tokens)

      # 2. Right-to-left token isolation: duration or timing can appear in either trailing order
      {duration_1, tokens_after_dur} = extract_duration(tokens_after_form)
      {timing_1, tokens_after_timing} = extract_timing(tokens_after_dur)

      {timing_2, tokens_after_timing_first} = extract_timing(tokens_after_form)
      {duration_2, tokens_after_dur_first} = extract_duration(tokens_after_timing_first)

      {timing_code, duration_expr, remaining_tokens} =
        if duration_1 && timing_1 do
          {timing_1, duration_1, tokens_after_timing}
        else
          {timing_2, duration_2, tokens_after_dur_first}
        end

      # 3. Extract dosage matrix or liquid measure (e.g., 1+0+1 or 1 tsp, 2 drops)
      {dosage_matrix, remaining_after_dosage} = extract_dosage_matrix(remaining_tokens)

      strength_hint = extract_strength_hint(remaining_after_dosage)
      drug_query = Enum.join(remaining_after_dosage, " ")

      %ParsedShorthand{
        raw_input: trimmed,
        drug_query: drug_query,
        dosage_form_hint: form_hint,
        strength_hint: strength_hint,
        dosage_matrix: dosage_matrix || :as_directed,
        duration_expression: duration_expr || :as_needed,
        timing_code: timing_code,
        special_instruction: nil
      }
    end
  end

  defp extract_form_prefix([]), do: {nil, []}

  defp extract_form_prefix([first | rest] = tokens) do
    case Map.get(@form_prefixes, String.downcase(first)) do
      nil -> {nil, tokens}
      form -> {form, rest}
    end
  end

  # Scans remaining drug tokens for explicit strength patterns (e.g. 500, 100ml, 500mg, 20mg)
  defp extract_strength_hint(tokens) do
    Enum.find_value(tokens, fn token ->
      cond do
        Regex.match?(~r/^\d+(?:mg|ml|mcg|g|iu|%|mg\/5ml)$/i, token) ->
          token

        Regex.match?(~r/^\d+$/, token) and token not in ["1", "2", "3", "4", "5"] ->
          token

        true ->
          nil
      end
    end)
  end

  defp extract_timing([]), do: {nil, []}

  defp extract_timing(tokens) do
    last_token = List.last(tokens) |> String.downcase()

    case Map.get(@timing_tokens, last_token) do
      nil ->
        {nil, tokens}

      code ->
        {code, Enum.slice(tokens, 0..-2//1)}
    end
  end

  defp extract_duration([]), do: {nil, []}

  defp extract_duration(tokens) do
    last_token = List.last(tokens) |> String.downcase()

    cond do
      Regex.match?(~r/^(\d+)d(?:ays?)?$/, last_token) ->
        [_, days] = Regex.run(~r/^(\d+)d(?:ays?)?$/, last_token)
        {"#{days} days", Enum.slice(tokens, 0..-2//1)}

      Regex.match?(~r/^(\d+)w(?:eeks?)?$/, last_token) ->
        [_, weeks] = Regex.run(~r/^(\d+)w(?:eeks?)?$/, last_token)
        {"#{weeks} weeks", Enum.slice(tokens, 0..-2//1)}

      Regex.match?(~r/^(\d+)m(?:onths?)?$/, last_token) ->
        [_, months] = Regex.run(~r/^(\d+)m(?:onths?)?$/, last_token)
        {"#{months} months", Enum.slice(tokens, 0..-2//1)}

      true ->
        {nil, tokens}
    end
  end

  defp extract_dosage_matrix([]), do: {nil, []}

  defp extract_dosage_matrix(tokens) do
    last_token = List.last(tokens)

    cond do
      # Matrix format (e.g. 1+0+1, 1-0-1, 1/2+0+0)
      Regex.match?(~r/^\d+(?:\/\d+)?(?:[\+\-]\d+(?:\/\d+)?)+$/, last_token) ->
        normalized = String.replace(last_token, "-", "+")
        {normalized, Enum.slice(tokens, 0..-2//1)}

      # Two-token measure (e.g. "1 tsp", "2 drops", "1 puff")
      length(tokens) >= 2 and
        String.downcase(last_token) in ["tsp", "drops", "drop", "puff", "puffs"] and
          Regex.match?(~r/^\d+(?:\/\d+)?$/, Enum.at(tokens, -2)) ->
        num = Enum.at(tokens, -2)
        measure = "#{num} #{last_token}"
        {measure, Enum.slice(tokens, 0..-3//1)}

      # Combined measure token (e.g. "1tsp", "2drops")
      Regex.match?(~r/^\d+(?:tsp|drops?|puffs?)$/i, last_token) ->
        {last_token, Enum.slice(tokens, 0..-2//1)}

      true ->
        {nil, tokens}
    end
  end
end
