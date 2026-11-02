defmodule RxGenerator.Prescriptions.PrescriberAirgapAuditTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Repo

  setup do
    {:ok, prescriber} =
      Prescriptions.create_prescriber_profile(%{
        name: "Dr. Audit Practitioner",
        bmdc_no: "A-88888",
        qualifications: "MBBS, FCPS",
        specialty: "General Medicine",
        active: true
      })

    {:ok, chamber1} =
      Prescriptions.create_chamber(%{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Chamber Audit Central",
        address: "Road 1, Dhanmondi, Dhaka",
        visiting_hours: "5 PM - 9 PM",
        contact_phone: "01700000000",
        is_default: true,
        active: true
      })

    {:ok, chamber2} =
      Prescriptions.create_chamber(%{
        prescriber_profile_id: prescriber.id,
        chamber_name: "Chamber Audit Branch",
        address: "Road 10, Uttara, Dhaka",
        visiting_hours: "2 PM - 5 PM",
        contact_phone: "01800000000",
        is_default: false,
        active: true
      })

    drug =
      Repo.all(DrugCatalogItem)
      |> List.first()

    %{prescriber: prescriber, chamber1: chamber1, chamber2: chamber2, drug: drug}
  end

  describe "T026: Edge-Native Air-gap & Performance SLA Audit (Article V & SC-001)" do
    test "executes prescriber setup, chamber switching, vault encryption, and signing with zero outbound network calls",
         %{prescriber: prescriber, chamber1: _c1, chamber2: c2, drug: drug} do
      test_pid = self()

      # Register prescriber in ProviderRegistry with bootstrapped key
      {:ok, {pub_key, _priv_key}} = Crypto.get_or_bootstrap_signing_key()

      RxGenerator.Prescriptions.ProviderRegistry.register_provider(prescriber.bmdc_no, %{
        name: prescriber.name,
        public_key: pub_key,
        status: :active
      })

      telemetry_ref =
        :telemetry_test.attach_event_handlers(test_pid, [
          [:finch, :request, :start],
          [:finch, :connect, :start],
          [:req, :request, :start]
        ])

      # 1. Draft creation with vault encryption
      assert {:ok, draft} =
               Prescriptions.create_draft(%{
                 patient_name: "Airgap Patient",
                 patient_phone: "+8801700000000",
                 patient_age: "40",
                 clinical_notes: "Audit test notes"
               })

      # 2. Chamber switching on draft
      assert {:ok, updated_draft} = Prescriptions.set_prescription_chamber(draft, c2.id)
      assert updated_draft.chamber_config_id == c2.id

      # 3. Patient vault update
      assert {:ok, vaulted_draft} =
               Prescriptions.update_patient_details(updated_draft, %{
                 patient_name: "Airgap Verified Patient",
                 clinical_notes: "Airgap notes verified"
               })

      # 4. Item addition and prescription finalization with Ed25519 digital signature
      assert {:ok, _item} =
               Prescriptions.add_item_to_draft(
                 vaulted_draft,
                 drug,
                 %{
                   dosage_matrix: "1+0+1",
                   duration_expression: "7 days",
                   timing_instruction: "pc"
                 },
                 1
               )

      assert {:ok, locked} = Prescriptions.finalize_prescription(vaulted_draft)
      assert locked.state == :locked
      assert is_binary(locked.canonical_manifest)
      assert is_binary(locked.signature)

      # 5. Offline verification
      qr_payload = Crypto.build_qr_payload(locked.canonical_manifest, locked.signature)
      assert {:ok, result} = Crypto.verify_qr_payload(qr_payload)
      assert result.valid? == true

      # Assert zero outbound network events were emitted
      refute_receive {[:finch, :request, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:finch, :connect, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:req, :request, :start], _id, _measurements, _metadata}, 50

      :telemetry.detach(telemetry_ref)
    end

    test "sub-15ms chamber switching latency SLA (SC-001)", %{chamber2: c2} do
      {:ok, draft} = Prescriptions.create_draft()

      # Benchmark 10 consecutive chamber switches
      durations_micro =
        for _i <- 1..10 do
          {micro, {:ok, _updated}} =
            :timer.tc(fn ->
              Prescriptions.set_prescription_chamber(draft, c2.id)
            end)

          micro
        end

      avg_ms = Enum.sum(durations_micro) / length(durations_micro) / 1000.0

      # Assert average round-trip is strictly below 15ms (SC-001 requires under 100ms / 15ms target)
      assert avg_ms < 15.0, "Average chamber switching latency #{avg_ms}ms exceeds 15ms SLA"
    end
  end
end
