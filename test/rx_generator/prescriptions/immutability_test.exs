defmodule RxGenerator.Prescriptions.ImmutabilityTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem
  alias RxGenerator.Test.FormularyFixtures

  require Ash.Query

  setup do
    try do
      RxGenerator.Repo.query!("DELETE FROM drug_catalog;")
    rescue
      _ -> :ok
    end

    FormularyFixtures.seed_catalog!()
    :ok
  end

  defp get_sample_drug do
    [drug | _] = Ash.read!(DrugCatalogItem)
    drug
  end

  describe "Prescription finalization (:lock transition)" do
    test "rejects locking an empty draft prescription" do
      {:ok, empty_draft} =
        Prescriptions.create_draft(%{rx_number: "RX-TEST-EMPTY", prescriber_bmdc_no: "A-12345"})

      assert {:error, error} = Prescriptions.finalize_prescription(empty_draft)
      assert error != nil

      # Ensure state remained draft in database
      reloaded = Ash.get!(Prescription, empty_draft.id)
      assert reloaded.state == :draft
    end

    test "transitions state from :draft to :locked when items are present" do
      {:ok, draft} =
        Prescriptions.create_draft(%{rx_number: "RX-TEST-001", prescriber_bmdc_no: "A-12345"})

      drug = get_sample_drug()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "pc"
      }

      {:ok, _item} = Prescriptions.add_item_to_draft(draft, drug, shorthand, 0)

      assert {:ok, locked} = Prescriptions.finalize_prescription(draft)
      assert locked.state == :locked
      assert locked.finalized_at != nil

      reloaded = Ash.get!(Prescription, draft.id)
      assert reloaded.state == :locked
      assert reloaded.finalized_at != nil
    end
  end

  describe "Immutability invariant on locked prescriptions" do
    setup do
      {:ok, draft} =
        Prescriptions.create_draft(%{rx_number: "RX-TEST-LOCKED", prescriber_bmdc_no: "A-12345"})

      drug = get_sample_drug()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "5 days",
        timing_code: "pc"
      }

      {:ok, item} = Prescriptions.add_item_to_draft(draft, drug, shorthand, 0)
      {:ok, locked} = Prescriptions.finalize_prescription(draft)

      %{locked: locked, item: item, drug: drug}
    end

    test "prohibits adding new items to locked prescription", %{locked: locked, drug: drug} do
      shorthand2 = %{
        dosage_matrix: "0+0+1",
        duration_expression: "3 days",
        timing_code: "hs"
      }

      assert {:error, _} = Prescriptions.add_item_to_draft(locked, drug, shorthand2, 1)

      # Assert no second line item was written to SQLite
      items =
        PrescriptionItem
        |> Ash.Query.filter(prescription_id == ^locked.id)
        |> Ash.read!()

      assert length(items) == 1
    end

    test "prohibits updating items belonging to locked prescription", %{item: item} do
      assert {:error, _} =
               item
               |> Ash.Changeset.for_update(:update, %{dosage_matrix: "2+0+2"})
               |> Ash.update()

      # Assert value remained unaltered in SQLite
      reloaded = Ash.get!(PrescriptionItem, item.id)
      assert reloaded.dosage_matrix == "1+0+1"
    end

    test "prohibits soft-deleting via boundary function on locked prescription", %{item: item} do
      assert {:error, _} = Prescriptions.remove_item(item.id)

      # Assert item was NOT soft-deleted
      reloaded = Ash.get!(PrescriptionItem, item.id)
      assert is_nil(reloaded.archived_at)
    end

    test "prohibits direct Ash.destroy on item belonging to locked prescription", %{item: item} do
      assert {:error, _} = Ash.destroy(item)

      # Assert item was NOT soft-deleted via direct Ash.destroy call
      reloaded = Ash.get!(PrescriptionItem, item.id)
      assert is_nil(reloaded.archived_at)
    end
  end
end
