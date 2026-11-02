defmodule RxGenerator.Prescriptions.Manifest do
  @moduledoc """
  Encapsulates the deterministic canonical manifest data structure and serialization
  for tamper-evident Ed25519 cryptographic signing and compact QR code rendering.

  Manifest V2 Canonical Schema:
  `v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>|<serialized_item_1>|<serialized_item_2>|...`
  """

  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem

  @version "v2"

  @enforce_keys [:version, :rx_number, :prescriber_bmdc_no, :chamber_token, :timestamp, :items]
  defstruct [:version, :rx_number, :prescriber_bmdc_no, :chamber_token, :timestamp, :items]

  @type item_token :: {
          short_drug_id :: String.t(),
          dosage_matrix :: String.t(),
          duration :: String.t(),
          timing :: String.t()
        }

  @type t :: %__MODULE__{
          version: String.t(),
          rx_number: String.t(),
          prescriber_bmdc_no: String.t(),
          chamber_token: String.t(),
          timestamp: integer(),
          items: [item_token()]
        }

  @doc """
  Compiles a deterministic canonical manifest string from a Prescription and its items.

  Rules (Manifest V2):
  1. Header: `v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>`
  2. Timestamp is integer seconds since Unix epoch (DateTime.to_unix/2).
  3. Items are sorted strictly by `display_order ASC`, then `id ASC`.
  4. Active items only (archived_at is nil).
  5. Delimiters `|` and `:` inside values are sanitized to `_`.
  6. Drug ID is truncated to an 8-character prefix.
  7. Item format: `<short_drug_id>:<matrix>:<duration>:<timing>`.
  """
  @spec compile(Prescription.t(), [PrescriptionItem.t()]) :: String.t()
  def compile(%Prescription{} = prescription, items) when is_list(items) do
    rx_number = sanitize_delimiter(prescription.rx_number || "")
    bmdc_no = sanitize_delimiter(prescription.prescriber_bmdc_no || "A-00000")
    chamber_token = compute_chamber_token(prescription)

    epoch_seconds =
      case prescription.finalized_at do
        %DateTime{} = dt -> DateTime.to_unix(dt, :second)
        _ -> DateTime.to_unix(DateTime.utc_now(), :second)
      end

    active_items =
      items
      |> Enum.filter(&is_nil(&1.archived_at))
      |> Enum.sort_by(fn item -> {item.display_order || 0, item.id || ""} end)

    if active_items == [] do
      raise ArgumentError,
            "Cannot compile canonical manifest for prescription with zero active medications"
    else
      serialized_items = Enum.map(active_items, &serialize_item/1)

      parts =
        [@version, rx_number, bmdc_no, chamber_token, to_string(epoch_seconds)] ++
          serialized_items

      Enum.join(parts, "|")
    end
  end

  @doc """
  Compiles a manifest string directly from a loaded Prescription struct.
  """
  @spec compile(Prescription.t()) :: String.t()
  def compile(%Prescription{items: items} = prescription) when is_list(items) do
    compile(prescription, items)
  end

  @doc """
  Computes a compact, URL-safe/canonical chamber token for the manifest header.
  Prefers slugified chamber name (truncated to 16 chars) or an 8-char chamber UUID prefix.
  Defaults to "general" if unassigned.
  """
  @spec compute_chamber_token(Prescription.t()) :: String.t()
  def compute_chamber_token(%Prescription{} = prescription) do
    name = prescription.chamber_name
    id = prescription.chamber_config_id

    cond do
      is_binary(name) and String.trim(name) != "" ->
        name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "_")
        |> String.trim("_")
        |> String.slice(0, 16)
        |> sanitize_delimiter()

      is_binary(id) and String.trim(id) != "" ->
        id
        |> String.replace("-", "")
        |> String.slice(0, 8)
        |> sanitize_delimiter()

      true ->
        "general"
    end
  end

  defp serialize_item(%PrescriptionItem{} = item) do
    short_id =
      item.drug_catalog_item_id
      |> to_string()
      |> String.replace("-", "")
      |> binary_part(0, 8)

    matrix = sanitize_delimiter(to_string(item.dosage_matrix || ""))
    duration = sanitize_delimiter(to_string(item.duration_expression || ""))
    timing = sanitize_delimiter(to_string(item.timing_instruction || ""))

    "#{short_id}:#{matrix}:#{duration}:#{timing}"
  end

  @doc """
  Sanitizes internal delimiter characters (`|` and `:`) by replacing them with `_`.
  """
  @spec sanitize_delimiter(String.t()) :: String.t()
  def sanitize_delimiter(string) when is_binary(string) do
    String.replace(string, ~r/[|:]/, "_")
  end
end
