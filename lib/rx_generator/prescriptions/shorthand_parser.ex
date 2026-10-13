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
    "after meal" => :pc,
    "before meal" => :ac,
    "bedtime" => :hs
  }

  @doc """
  Parses a raw shorthand string (e.g. "napa xtra 1+0+1 5d pc") into a %ParsedShorthand{}.
  """
  def parse(raw_input) when is_binary(raw_input) do
    trimmed = String.trim(raw_input)
    tokens = String.split(trimmed, ~r/\s+/, trim: true)

    {timing_code, remaining_after_timing} = extract_timing(tokens)
    {duration_expr, remaining_after_duration} = extract_duration(remaining_after_timing)
    {dosage_matrix, remaining_after_dosage} = extract_dosage_matrix(remaining_after_duration)

    drug_query = Enum.join(remaining_after_dosage, " ")

    %ParsedShorthand{
      raw_input: trimmed,
      drug_query: drug_query,
      strength_hint: nil,
      dosage_matrix: dosage_matrix || :as_directed,
      duration_expression: duration_expr || :as_needed,
      timing_code: timing_code,
      special_instruction: nil
    }
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

    if Regex.match?(~r/^\d+(?:\/\d+)?(?:\+\d+(?:\/\d+)?)+$/, last_token) do
      {last_token, Enum.slice(tokens, 0..-2//1)}
    else
      {nil, tokens}
    end
  end
end

