defmodule RxGenerator.Prescriptions.PersistentDraftsTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Repo

  setup do
    Repo.query!("DELETE FROM prescription_items;")
    Repo.query!("DELETE FROM prescriptions;")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ai")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_ad")
    Repo.query!("DROP TRIGGER IF EXISTS drug_catalog_au")
    Repo.query!("DELETE FROM drug_catalog;")
    Repo.query!("DELETE FROM drug_catalog_fts;")

    now = DateTime.utc_now()

    drug1 = %{
      id: Ash.UUID.generate(),
      brand_name: "Napa Extra",
      generic_name: "Paracetamol + Caffeine",
      strength: "500 mg + 65 mg",
      dosage_form: "Tablet",
      manufacturer: "Beximco Pharmaceuticals Ltd",
      dgda_reg_no: "002-0020-030",
      is_controlled: false,
      inserted_at: now,
      updated_at: now
    }

    drug2 = %{
      id: Ash.UUID.generate(),
      brand_name: "Rivotril",
      generic_name: "Clonazepam",
      strength: "0.5 mg",
      dosage_form: "Tablet",
      manufacturer: "Radiant Pharmaceuticals Ltd",
      dgda_reg_no: "040-0010-010",
      is_controlled: true,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(DrugCatalogItem, [drug1, drug2])

    [
      drug1: Ash.get!(DrugCatalogItem, drug1.id),
      drug2: Ash.get!(DrugCatalogItem, drug2.id)
    ]
  end

  describe "Prescription draft persistence & work resumption (Article I & VIII)" do
    test "creates active draft and reloads it across sessions with items ordered by display_order",
         %{drug1: drug1, drug2: drug2} do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()
      assert draft.state == :draft

      # Add first item
      shorthand1 = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, item1} = Prescriptions.add_item_to_draft(draft, drug1, shorthand1, 0)
      assert item1.brand_name_snapshot == "Napa Extra"
      assert item1.generic_name_snapshot == "Paracetamol + Caffeine"
      assert item1.strength_snapshot == "500 mg + 65 mg"
      assert item1.dosage_form_snapshot == "Tablet"
      assert item1.is_controlled_snapshot == false

      # Add second item
      shorthand2 = %{
        dosage_matrix: "0+0+1",
        duration_expression: "14 days",
        timing_code: "at_bedtime"
      }

      assert {:ok, item2} = Prescriptions.add_item_to_draft(draft, drug2, shorthand2, 1)
      assert item2.is_controlled_snapshot == true

      # Reload draft via domain interface
      assert {:ok, reloaded} = Prescriptions.get_active_draft()
      assert length(reloaded.items) == 2
      assert Enum.at(reloaded.items, 0).id == item1.id
      assert Enum.at(reloaded.items, 1).id == item2.id
    end

    test "soft-archival: removes item by setting archived_at and excludes it from draft renders",
         %{drug1: drug1} do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, item} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)

      # Ensure 1 active item
      assert {:ok, loaded} = Prescriptions.get_active_draft()
      assert length(loaded.items) == 1

      # Remove item via domain interface
      assert :ok = Prescriptions.remove_item(item.id)

      # Invariant: Item row is NOT deleted from SQLite, but has archived_at set
      raw_item = Repo.get!(RxGenerator.Prescriptions.PrescriptionItem, item.id)
      refute is_nil(raw_item.archived_at)

      # Invariant: Reloading draft must exclude soft-archived items (no ghost items)
      assert {:ok, reloaded} = Prescriptions.get_active_draft()
      assert reloaded.items == []
    end

    test "allows re-prescribing the same drug after previous instance was soft-archived", %{
      drug1: drug1
    } do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, item1} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)
      assert :ok = Prescriptions.remove_item(item1.id)

      # Re-adding the same drug should succeed because the active index ignores archived rows
      assert {:ok, item2} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)
      assert item2.id != item1.id

      assert {:ok, loaded} = Prescriptions.get_active_draft()
      assert length(loaded.items) == 1
      assert hd(loaded.items).id == item2.id
    end

    test "prevents duplicate active items for the same drug in the same prescription", %{
      drug1: drug1
    } do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, _item1} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)

      # Adding again while active must fail
      assert {:error, _error} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 1)
    end
  end

  describe "Locked prescription immutability (State Machine Invariant)" do
    test "transitions from draft to locked", %{drug1: drug1} do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, _item} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)

      assert {:ok, locked} = Prescriptions.lock_prescription(draft)
      assert locked.state == :locked
    end

    test "rejects adding new items when prescription is locked", %{drug1: drug1, drug2: drug2} do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, _item} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)

      assert {:ok, locked} = Prescriptions.lock_prescription(draft)

      # Adding item to locked prescription must fail validation
      assert {:error, _err} = Prescriptions.add_item_to_draft(locked, drug2, shorthand, 1)
    end

    test "rejects removing items when prescription is locked", %{drug1: drug1} do
      assert {:ok, draft} = Prescriptions.get_or_create_active_draft()

      shorthand = %{
        dosage_matrix: "1+0+1",
        duration_expression: "7 days",
        timing_code: "after_meal"
      }

      assert {:ok, item} = Prescriptions.add_item_to_draft(draft, drug1, shorthand, 0)

      assert {:ok, _locked} = Prescriptions.lock_prescription(draft)

      # Removing item from locked prescription must fail validation
      assert {:error, _err} = Prescriptions.remove_item(item.id)
    end
  end
end
