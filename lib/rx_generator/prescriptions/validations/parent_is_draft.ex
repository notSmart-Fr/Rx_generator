defmodule RxGenerator.Prescriptions.Validations.ParentIsDraft do
  @moduledoc """
  Validates that the parent prescription of a PrescriptionItem is in :draft state.
  Prevents modifications, additions, or deletions on locked prescriptions.
  """
  use Ash.Resource.Validation

  alias RxGenerator.Prescriptions.Prescription

  @impl true
  def validate(changeset, _opts, _context) do
    prescription_id =
      Ash.Changeset.get_attribute(changeset, :prescription_id) ||
        (changeset.data && changeset.data.prescription_id)

    case prescription_id do
      nil ->
        {:error, "Prescription ID must be present"}

      pid ->
        case Ash.get(Prescription, pid) do
          {:ok, %{state: :draft}} ->
            :ok

          {:ok, %{state: state}} ->
            {:error,
             field: :prescription_id,
             message: "cannot mutate prescription items on a #{state} prescription"}

          {:error, error} ->
            {:error, error}
        end
    end
  end
end
