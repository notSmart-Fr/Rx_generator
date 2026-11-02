defmodule RxGenerator.Support.PrescriberFixtures do
  @moduledoc """
  Test fixture helpers for PrescriberProfile, ChamberConfig, and Encrypted Patient Data.
  """

  alias RxGenerator.Repo

  @default_bmdc "A-12345"
  @default_doctor_name "Dr. Tariqul Islam"
  @default_qualifications "MBBS (DMC), FCPS (Medicine)"
  @default_specialty "Medicine Specialist & Interventional Cardiologist"

  @doc """
  Generates raw or map attributes for a PrescriberProfile.
  """
  def valid_prescriber_attrs(attrs \\ %{}) do
    unique_suffix = System.unique_integer([:positive])

    Enum.into(attrs, %{
      name: @default_doctor_name,
      bmdc_no: "A-#{10000 + rem(unique_suffix, 89999)}",
      qualifications: @default_qualifications,
      specialty: @default_specialty,
      active: true
    })
  end

  @doc """
  Inserts a raw prescriber_profile record directly into SQLite for test isolation.
  """
  def insert_raw_prescriber_profile(attrs \\ %{}) do
    id = attrs[:id] || Ash.UUID.generate()
    now = DateTime.utc_now()
    attrs = valid_prescriber_attrs(attrs)

    query = """
    INSERT INTO prescriber_profiles (id, name, bmdc_no, qualifications, specialty, active, inserted_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    Repo.query!(query, [
      id,
      attrs.name,
      attrs.bmdc_no,
      attrs.qualifications,
      attrs.specialty,
      if(attrs.active, do: 1, else: 0),
      now,
      now
    ])

    Map.merge(attrs, %{id: id, inserted_at: now, updated_at: now})
  end

  @doc """
  Generates raw or map attributes for a ChamberConfig.
  """
  def valid_chamber_attrs(prescriber_profile_id, attrs \\ %{}) do
    Enum.into(attrs, %{
      prescriber_profile_id: prescriber_profile_id,
      chamber_name: "Popular Diagnostic Centre, Dhanmondi",
      hospital_name: "Building 2, Room 402",
      address: "House 16, Road 2, Dhanmondi R/A, Dhaka-1205",
      visiting_hours: "5:00 PM - 9:00 PM (Sat - Thu)",
      contact_phone: "+880 1711-000000",
      is_default: false,
      active: true
    })
  end

  @doc """
  Inserts a raw chamber_config record directly into SQLite for test isolation.
  """
  def insert_raw_chamber(prescriber_profile_id, attrs \\ %{}) do
    id = attrs[:id] || Ash.UUID.generate()
    now = DateTime.utc_now()
    attrs = valid_chamber_attrs(prescriber_profile_id, attrs)

    query = """
    INSERT INTO chamber_configs (id, prescriber_profile_id, chamber_name, hospital_name, address, visiting_hours, contact_phone, is_default, active, inserted_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    Repo.query!(query, [
      id,
      prescriber_profile_id,
      attrs.chamber_name,
      attrs.hospital_name,
      attrs.address,
      attrs.visiting_hours,
      attrs.contact_phone,
      if(attrs.is_default, do: 1, else: 0),
      if(attrs.active, do: 1, else: 0),
      now,
      now
    ])

    Map.merge(attrs, %{id: id, inserted_at: now, updated_at: now})
  end

  @doc """
  Default BM&DC number constant for tests.
  """
  def default_bmdc_no, do: @default_bmdc

  @doc """
  Default doctor name constant for tests.
  """
  def default_doctor_name, do: @default_doctor_name
end
