defmodule RxGenerator.Repo.Migrations.AddPrescriptionSigningFields do
  use Ecto.Migration

  def change do
    alter table(:prescriptions) do
      add :canonical_manifest, :text
      add :signature, :text
      add :finalized_at, :utc_datetime_usec
    end
  end
end
