defmodule RxGenerator.Prescriptions do
  use Ash.Domain,
    otp_app: :rx_generator

  require Ash.Query
  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions.BengaliTranslator
  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Prescriptions.PrescriptionItem

  resources do
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
  Creates a new draft prescription.
  """
  def create_draft(attrs \\ %{}) do
    rx_number = Map.get(attrs, :rx_number) || generate_rx_number()

    params =
      attrs
      |> Map.put(:rx_number, rx_number)
      |> Map.put_new(:patient_name, "Walk-in Patient")
      |> Map.put_new(:prescriber_bmdc_no, "A-12345")

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
  Transitions a draft prescription to :locked state.
  """
  def lock_prescription(%Prescription{} = prescription) do
    prescription
    |> Ash.Changeset.for_update(:lock, %{})
    |> Ash.update()
  end

  defp generate_rx_number do
    date_part = Date.utc_today() |> Date.to_iso8601() |> String.replace("-", "")
    random_part = :crypto.strong_rand_bytes(3) |> Base.encode16()
    "RX-#{date_part}-#{random_part}"
  end
end
