defmodule RxGenerator.Printing.Spooler do
  @moduledoc """
  Hardware interface behaviour and dispatcher for finalized prescriptions to physical or virtual print spoolers.
  """

  alias RxGenerator.Prescriptions.Prescription

  @type spool_opt :: {:copies, pos_integer()} | {:printer_name, String.t()} | {:duplex, boolean()}
  @type spool_result :: :ok | {:error, reason :: term()}

  @callback spool(prescription :: Prescription.t(), opts :: [spool_opt()]) :: spool_result()

  @doc """
  Dispatches a prescription to the configured print spooler adapter.
  Enforces that the prescription is in :locked state and options are valid.
  """
  @spec spool(Prescription.t(), keyword()) :: spool_result()
  def spool(%Prescription{} = prescription, opts \\ []) do
    with :ok <- validate_prescription_state(prescription),
         :ok <- validate_opts(opts) do
      impl().spool(prescription, opts)
    end
  end

  defp validate_prescription_state(%Prescription{state: :locked}), do: :ok
  defp validate_prescription_state(%Prescription{}), do: {:error, :unfinalized_prescription}

  defp validate_opts(opts) do
    case Keyword.get(opts, :copies, 1) do
      copies when is_integer(copies) and copies >= 1 and copies <= 10 ->
        :ok

      _ ->
        {:error, :invalid_copy_count}
    end
  end

  defp impl do
    Application.get_env(:rx_generator, :print_spooler, RxGenerator.Printing.OSSpooler)
  end
end
