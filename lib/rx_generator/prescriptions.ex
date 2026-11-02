defmodule RxGenerator.Prescriptions do
  @moduledoc """
  Domain interface for clinical prescriptions and prescribed medication line items.
  """
  use Ash.Domain,
    otp_app: :rx_generator

  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions.BengaliTranslator
  alias RxGenerator.Prescriptions.ChamberConfig
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.Manifest
  alias RxGenerator.Prescriptions.PrescriberProfile
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem

  resources do
    resource PrescriberProfile do
      define :create_prescriber_profile, action: :create
      define :list_prescriber_profiles, action: :read
      define :update_prescriber_profile, action: :update
    end

    resource ChamberConfig do
      define :create_chamber, action: :create
      define :list_chambers, action: :read
      define :update_chamber, action: :update
    end

    resource Prescription do
      define :create_prescription, action: :create
      define :list_prescriptions, action: :read
    end

    resource PrescriptionItem do
      define :create_item, action: :create
      define :list_items, action: :read
    end
  end

  @doc """
  Retrieves the active prescriber profile, returning `{:ok, profile}` or `{:error, :not_found}`.
  """
  def get_active_prescriber do
    PrescriberProfile
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read()
    |> case do
      {:ok, [profile | _]} -> {:ok, profile}
      {:ok, []} -> {:error, :not_found}
      {:error, err} -> {:error, err}
    end
  end

  @doc """
  Updates patient demographic and clinical details on a draft prescription.
  """
  def update_patient_details(%Prescription{} = prescription, params) when is_map(params) do
    prescription
    |> Ash.Changeset.for_update(:update_patient_details, params)
    |> Ash.update()
  end

  @doc """
  Lists active chambers for a prescriber profile.
  """
  def list_chambers_for_prescriber(prescriber_profile_id) when is_binary(prescriber_profile_id) do
    ChamberConfig
    |> Ash.Query.for_read(:list_for_prescriber, %{prescriber_profile_id: prescriber_profile_id})
    |> Ash.read()
  end

  @doc """
  Sets a chamber as the default for its prescriber.
  """
  def set_default_chamber(%ChamberConfig{} = chamber) do
    chamber
    |> Ash.Changeset.for_update(:set_as_default, %{})
    |> Ash.update()
  end

  @doc """
  Sets the active chamber on a draft prescription, snapshotting its details.
  """
  def set_prescription_chamber(%Prescription{} = prescription, chamber_id)
      when is_binary(chamber_id) do
    case Ash.get(ChamberConfig, chamber_id) do
      {:ok, chamber} ->
        if not chamber.active do
          {:error, :inactive_chamber}
        else
          attrs = %{
            chamber_config_id: chamber.id,
            chamber_name: chamber.chamber_name,
            chamber_address: chamber.address,
            chamber_schedule: chamber.visiting_hours,
            chamber_phone: chamber.contact_phone
          }

          prescription
          |> Ash.Changeset.for_update(:set_chamber, attrs)
          |> Ash.update()
        end

      error ->
        error
    end
  end

  @doc """
  Retrieves the active draft prescription with active items loaded.
  Returns `{:ok, prescription}` or `{:error, :not_found}`.
  """
  def get_active_draft do
    Prescription
    |> Ash.Query.filter(state == :draft)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(:items)
    |> Ash.read()
    |> case do
      {:ok, [draft | _]} -> {:ok, draft}
      {:ok, []} -> {:error, :not_found}
      {:error, err} -> {:error, err}
    end
  end

  @doc """
  Gets the active draft or creates a new one with a unique rx_number if none exists.
  """
  def get_or_create_active_draft do
    case get_active_draft() do
      {:ok, draft} ->
        {:ok, draft}

      {:error, :not_found} ->
        create_draft()

      {:error, err} ->
        {:error, err}
    end
  end

  @doc """
  Creates a new draft prescription, automatically linking the active prescriber profile
  if one is configured.
  """
  def create_draft(attrs \\ %{}) do
    rx_number = Map.get(attrs, :rx_number) || generate_rx_number()

    active_prescriber =
      case get_active_prescriber() do
        {:ok, profile} -> profile
        _ -> nil
      end

    default_chamber =
      if active_prescriber do
        case list_chambers_for_prescriber(active_prescriber.id) do
          {:ok, [ch | _]} -> ch
          _ -> nil
        end
      else
        nil
      end

    params =
      attrs
      |> Map.put(:rx_number, rx_number)
      |> Map.put_new(:patient_name, "Walk-in Patient")
      |> Map.put_new(
        :prescriber_profile_id,
        active_prescriber && active_prescriber.id
      )
      |> Map.put_new(
        :prescriber_bmdc_no,
        (active_prescriber && active_prescriber.bmdc_no) || "A-12345"
      )
      |> Map.put_new(
        :prescriber_name,
        active_prescriber && active_prescriber.name
      )
      |> Map.put_new(
        :prescriber_qualifications,
        active_prescriber && active_prescriber.qualifications
      )
      |> Map.put_new(
        :chamber_config_id,
        default_chamber && default_chamber.id
      )
      |> Map.put_new(
        :chamber_name,
        default_chamber && default_chamber.chamber_name
      )
      |> Map.put_new(
        :chamber_address,
        default_chamber && default_chamber.address
      )
      |> Map.put_new(
        :chamber_schedule,
        default_chamber && default_chamber.visiting_hours
      )
      |> Map.put_new(
        :chamber_phone,
        default_chamber && default_chamber.contact_phone
      )

    Prescription
    |> Ash.Changeset.for_create(:create, params)
    |> Ash.create()
    |> case do
      {:ok, created} -> Ash.load(created, :items)
      error -> error
    end
  end

  @doc """
  Adds an item to a draft prescription by freezing the drug metadata snapshot.
  """
  def add_item_to_draft(
        %Prescription{id: rx_id},
        %DrugCatalogItem{} = drug,
        parsed_shorthand,
        display_order
      ) do
    dosage_matrix_str = to_string(Map.get(parsed_shorthand, :dosage_matrix, "1+0+1"))
    duration_str = to_string(Map.get(parsed_shorthand, :duration_expression, "7 days"))
    timing_str = parsed_shorthand[:timing_code] || parsed_shorthand[:timing_instruction]

    canonical_bengali =
      BengaliTranslator.to_canonical(
        dosage_matrix_str,
        duration_str,
        timing_str
      )

    bengali_breakdown =
      BengaliTranslator.to_breakdown(dosage_matrix_str)

    attrs = %{
      prescription_id: rx_id,
      drug_catalog_item_id: drug.id,
      brand_name_snapshot: drug.brand_name,
      generic_name_snapshot: drug.generic_name,
      dosage_form_snapshot: drug.dosage_form,
      strength_snapshot: drug.strength,
      is_controlled_snapshot: drug.is_controlled || false,
      dosage_matrix: dosage_matrix_str,
      duration_expression: duration_str,
      timing_instruction: timing_str && to_string(timing_str),
      canonical_bengali_text: canonical_bengali,
      bengali_breakdown_text: bengali_breakdown,
      display_order: display_order
    }

    PrescriptionItem
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  @doc """
  Removes a prescription item via soft archival (setting `archived_at`).
  """
  def remove_item(item_id) when is_binary(item_id) do
    case Ash.get(PrescriptionItem, item_id) do
      {:ok, item} ->
        case Ash.destroy(item) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, err} -> {:error, err}
        end

      {:error, err} ->
        {:error, err}
    end
  end

  @doc """
  Finalizes a draft prescription with atomic locking, cryptographic manifest generation,
  and Ed25519 offline signing.
  """
  def finalize_prescription(%Prescription{} = prescription, attrs \\ %{}) do
    prescription
    |> Ash.load([:items, :prescriber, :chamber])
    |> case do
      {:ok, loaded_rx} ->
        # Freeze prescriber and chamber snapshots if present
        prescriber =
          case loaded_rx.prescriber do
            %PrescriberProfile{} = p ->
              p

            _ ->
              case get_active_prescriber() do
                {:ok, p} -> p
                _ -> nil
              end
          end

        chamber =
          case loaded_rx.chamber do
            %ChamberConfig{} = c ->
              c

            _ ->
              if prescriber do
                case list_chambers_for_prescriber(prescriber.id) do
                  {:ok, [c | _]} -> c
                  _ -> nil
                end
              else
                nil
              end
          end

        # Determine finalized_at timestamp (preserving passed value if present)
        finalized_at =
          attrs[:finalized_at] || Map.get(attrs, "finalized_at") || DateTime.utc_now()

        active_items = Enum.filter(loaded_rx.items || [], &is_nil(&1.archived_at))

        if active_items == [] do
          loaded_rx
          |> Ash.Changeset.for_update(:lock, attrs)
          |> Ash.update()
        else
          rx_for_manifest = %{
            loaded_rx
            | finalized_at: finalized_at,
              prescriber_name: loaded_rx.prescriber_name || (prescriber && prescriber.name),
              prescriber_bmdc_no:
                loaded_rx.prescriber_bmdc_no || (prescriber && prescriber.bmdc_no),
              prescriber_qualifications:
                loaded_rx.prescriber_qualifications || (prescriber && prescriber.qualifications),
              chamber_name: loaded_rx.chamber_name || (chamber && chamber.chamber_name),
              chamber_address: loaded_rx.chamber_address || (chamber && chamber.address),
              chamber_schedule: loaded_rx.chamber_schedule || (chamber && chamber.visiting_hours),
              chamber_phone: loaded_rx.chamber_phone || (chamber && chamber.contact_phone)
          }

          manifest_string = Manifest.compile(rx_for_manifest, active_items)

          # Retrieve signing key and sign manifest
          with {:ok, {_pub_key, priv_key}} <- Crypto.get_or_bootstrap_signing_key(),
               {:ok, signature} <- Crypto.sign_manifest(manifest_string, priv_key) do
            lock_params =
              attrs
              |> Map.put(:canonical_manifest, manifest_string)
              |> Map.put(:signature, signature)
              |> Map.put(:finalized_at, finalized_at)
              |> Map.put_new(:prescriber_name, rx_for_manifest.prescriber_name)
              |> Map.put_new(:prescriber_bmdc_no, rx_for_manifest.prescriber_bmdc_no)
              |> Map.put_new(
                :prescriber_qualifications,
                rx_for_manifest.prescriber_qualifications
              )
              |> Map.put_new(:chamber_name, rx_for_manifest.chamber_name)
              |> Map.put_new(:chamber_address, rx_for_manifest.chamber_address)
              |> Map.put_new(:chamber_schedule, rx_for_manifest.chamber_schedule)
              |> Map.put_new(:chamber_phone, rx_for_manifest.chamber_phone)

            loaded_rx
            |> Ash.Changeset.for_update(:lock, lock_params)
            |> Ash.update()
          else
            {:error, reason} ->
              {:error, reason}
          end
        end

      error ->
        error
    end
  end

  @doc """
  Transitions a draft prescription to :locked state.
  """
  def lock_prescription(%Prescription{} = prescription, attrs \\ %{}) do
    finalize_prescription(prescription, attrs)
  end

  @doc """
  Verifies a prescription QR payload offline against the local provider registry.
  Returns `{:ok, %VerificationResult{status: :valid}}` or `{:error, %VerificationResult{}}`.
  """
  def verify_prescription_payload(payload) when is_binary(payload) do
    Crypto.verify_qr_payload(payload)
  end

  defp generate_rx_number do
    date_part = Date.utc_today() |> Date.to_iso8601() |> String.replace("-", "")
    random_part = :crypto.strong_rand_bytes(3) |> Base.encode16()
    "RX-#{date_part}-#{random_part}"
  end
end
