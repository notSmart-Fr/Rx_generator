defmodule RxGenerator.Prescriptions.VerificationResult do
  @moduledoc """
  Evaluation outcome for a scanned or parsed prescription QR verification payload.
  """

  @enforce_keys [:valid?, :status]
  defstruct [
    :valid?,
    :status,
    :rx_number,
    :prescriber_bmdc_no,
    :prescriber_name,
    :timestamp,
    :items,
    :error_message
  ]

  @type status ::
          :valid
          | :signature_mismatch
          | :unknown_signer
          | :license_inactive
          | :malformed_payload

  @type t :: %__MODULE__{
          valid?: boolean(),
          status: status(),
          rx_number: String.t() | nil,
          prescriber_bmdc_no: String.t() | nil,
          prescriber_name: String.t() | nil,
          timestamp: integer() | nil,
          items: list() | nil,
          error_message: String.t() | nil
        }
end
