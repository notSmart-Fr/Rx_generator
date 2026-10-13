defmodule RxGenerator.Prescriptions.ParsedShorthand do
  @moduledoc """
  Struct representing the deterministic token extraction output
  from a clinical shorthand string.
  """
  @enforce_keys [:raw_input, :drug_query]
  defstruct [
    :raw_input,
    :drug_query,
    :dosage_form_hint,
    :strength_hint,
    :dosage_matrix,
    :duration_expression,
    :timing_code,
    :special_instruction
  ]
end

