defmodule RxGenerator.Test.IngestionFixtures do
  @moduledoc """
  Fixtures and temporary CSV helpers for drug catalog ingestion testing.
  Provides representative 20-row DGDA samples covering:
  - Bulk chemicals (Kg, Liter, DRUM, Bulk, gm (raw)) to be skipped
  - Trailing combinations (Isoniazid + Rifampicin, Ethambutol + Isoniazid + Rifampicin)
  - Interspersed FDCs with + and & (Amoxicillin + Clavulanic Acid, Paracetamol & Caffeine)
  - Liquid / fractional units (10 mg/ml, 120 mg/5 ml)
  - Products lacking numerical strengths (Oral Rehydration Salt)
  - Scheduled narcotics (Morphine, Tramadol, Clonazepam, Alprazolam)
  - Messy dosage form casings (" capsule ")
  """

  @fixture_path Path.expand("../fixtures/dgda_sample.csv", __DIR__)

  @doc """
  Returns the path to the permanent 20-row DGDA sample fixture file.
  """
  def fixture_path, do: @fixture_path

  @doc """
  Returns raw sample CSV content as binary.
  """
  def sample_csv_content do
    if File.exists?(@fixture_path) do
      File.read!(@fixture_path)
    else
      ""
    end
  end

  @doc """
  Writes a sample CSV file to the provided path (or a default temporary path).
  """
  def create_sample_csv!(path \\ nil) do
    dest = path || Path.join(System.tmp_dir!(), "sample_medicines_#{Ash.UUID.generate()}.csv")
    File.write!(dest, sample_csv_content())
    dest
  end
end
