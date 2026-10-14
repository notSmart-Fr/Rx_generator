defmodule RxGenerator.Repo.Migrations.AddIsControlledSnapshotToPrescriptionItems do
  use Ecto.Migration

  def up do
    alter table(:prescription_items) do
      add :is_controlled_snapshot, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:prescription_items) do
      remove :is_controlled_snapshot
    end
  end
end
