defmodule RxGenerator.Printing.Spooler do
  @moduledoc """
  Hardware interface behaviour for dispatching finalized prescriptions to physical or virtual print spoolers.
  """

  alias RxGenerator.Prescriptions.Prescription

  @type spool_opt :: {:copies, pos_integer()} | {:printer_name, String.t()} | {:duplex, boolean()}
  @type spool_result :: :ok | {:error, reason :: term()}

  @callback spool(prescription :: Prescription.t(), opts :: [spool_opt()]) :: spool_result()
end
