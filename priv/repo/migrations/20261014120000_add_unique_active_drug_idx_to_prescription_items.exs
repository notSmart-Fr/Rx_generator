defmodule RxGenerator.Repo.Migrations.AddUniqueActiveDrugIdxToPrescriptionItems do
  use Ecto.Migration

  def up do
    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS prescription_items_unique_active_drug_idx
    ON prescription_items(prescription_id, drug_catalog_item_id)
    WHERE archived_at IS NULL;
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS prescription_items_unique_active_drug_idx;")
  end
end
