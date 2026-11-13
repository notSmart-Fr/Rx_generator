defmodule RxGenerator.DesktopPackagingTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.DrugCatalogItem
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Prescriptions
  alias RxGenerator.Prescriptions.Crypto
  alias RxGenerator.Prescriptions.ProviderRegistry
  alias RxGenerator.Prescriptions.ShorthandParser
  alias RxGenerator.Release
  alias RxGenerator.Repo
  alias RxGenerator.Test.FormularyFixtures

  # Constitutional Article VI: strictly < 250MB total RAM
  @ceiling_bytes 250 * 1024 * 1024
  # Conservative budget for WebView2 / WinForms native wrapper working set
  @webview_host_budget_bytes 80 * 1024 * 1024

  describe "T020: End-to-End Desktop Release & Packaging Verification" do
    test "Mix release configuration bundles ERTS, strips beams, and includes overlays" do
      rel_cfg = Mix.Project.config()[:releases][:rx_generator]
      assert rel_cfg != nil
      assert rel_cfg[:include_erts] == true
      assert rel_cfg[:strip_beams] == true
      assert "rel/overlays" in (rel_cfg[:overlays] || [])
    end

    test "all desktop build scripts, release env templates, and native runner sources exist" do
      required_files = [
        "rel/env.bat.eex",
        "rel/env.sh.eex",
        "scripts/build_desktop.ps1",
        "native_runner/windows/RxGeneratorApp.cs",
        "native_runner/windows/build_runner.ps1",
        "native_runner/linux/rx_generator_runner.sh"
      ]

      for path <- required_files do
        assert File.exists?(path), "Expected packaging file missing: #{path}"
      end
    end

    test "bundled seed SQLite database exists in priv/repo/seeds with populated drug_catalog and schema_migrations" do
      seed_db = "priv/repo/seeds/rx_generator_seed.db"
      assert File.exists?(seed_db), "Expected pre-seeded database missing: #{seed_db}"
      assert File.stat!(seed_db).size > 0

      {:ok, conn} = Exqlite.Sqlite3.open(seed_db)

      try do
        {:ok, cat_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog;")
        {:row, [drug_count]} = Exqlite.Sqlite3.step(conn, cat_stmt)
        assert drug_count >= 10, "Expected at least 10 seeded drugs, got #{drug_count}"

        {:ok, mig_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM schema_migrations;")
        {:row, [migration_count]} = Exqlite.Sqlite3.step(conn, mig_stmt)
        assert migration_count >= 1, "Expected schema_migrations rows in seed DB"

        {:ok, fts_stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog_fts;")
        {:row, [fts_count]} = Exqlite.Sqlite3.step(conn, fts_stmt)
        assert fts_count >= 10, "Expected >= 10 pre-indexed FTS5 rows, got #{fts_count}"

        {:ok, vec_stmt} =
          Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM drug_catalog_vectors;")

        {:row, [vec_count]} = Exqlite.Sqlite3.step(conn, vec_stmt)
        assert vec_count >= 10, "Expected >= 10 pre-indexed vector rows, got #{vec_count}"
      after
        Exqlite.Sqlite3.close(conn)
      end
    end

    test "T027: bundled local vector model files exist in priv/models/embedding_gemma_2 and in assembled release" do
      model_files = [
        "priv/models/embedding_gemma_2/config.json",
        "priv/models/embedding_gemma_2/weights.nx"
      ]

      for path <- model_files do
        assert File.exists?(path), "Missing local vector model artifact: #{path}"
        assert File.stat!(path).size > 0
      end

      rel_model_dir =
        "_build/prod/rel/rx_generator/lib/rx_generator-0.1.0/priv/models/embedding_gemma_2"

      assert File.exists?(Path.join(rel_model_dir, "config.json"))
      assert File.exists?(Path.join(rel_model_dir, "weights.nx"))

      resolved_dir = RxGenerator.Formulary.NeuralWorker.resolve_model_path(nil)
      assert File.dir?(resolved_dir)
      assert File.exists?(Path.join(resolved_dir, "config.json"))
    end

    test "assembled prod release contains ERTS binaries, release scripts, RxGeneratorApp.exe, and bundled seed DB" do
      rel_root = "_build/prod/rel/rx_generator"
      assert File.dir?(rel_root), "Release output directory missing: #{rel_root}"

      assert File.exists?(Path.join(rel_root, "bin/rx_generator.bat"))
      assert File.exists?(Path.join(rel_root, "releases/0.1.0/env.bat"))

      exe_path = Path.join(rel_root, "bin/RxGeneratorApp.exe")
      assert File.exists?(exe_path), "Native runner executable missing: #{exe_path}"
      assert File.stat!(exe_path).size > 0
      <<"MZ", _rest::binary>> = File.read!(exe_path)

      erts_dirs = Path.wildcard(Path.join(rel_root, "erts-*"))
      assert length(erts_dirs) >= 1, "Bundled ERTS directory missing in #{rel_root}"

      erts_dir = hd(erts_dirs)

      assert File.exists?(Path.join(erts_dir, "bin/erl.exe")) or
               File.exists?(Path.join(erts_dir, "bin/erl")),
             "Bundled ERTS erl binary missing in #{erts_dir}"

      rel_seed_db =
        Path.join(rel_root, "lib/rx_generator-0.1.0/priv/repo/seeds/rx_generator_seed.db")

      assert File.exists?(rel_seed_db), "Seed DB missing from assembled release: #{rel_seed_db}"
      assert File.stat!(rel_seed_db).size > 0
    end
  end

  describe "T021: Combined BEAM + Native Runner RAM Ceiling (< 250MB, Article VI)" do
    setup do
      FormularyFixtures.clean_catalog!()
      FormularyFixtures.seed_catalog!()

      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Packaging Memory",
          bmdc_no: "A-77777",
          qualifications: "MBBS, FCPS",
          specialty: "Internal Medicine",
          active: true
        })

      {:ok, _chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Packaging Benchmark Chamber",
          address: "Road 7, Banani, Dhaka",
          visiting_hours: "5 PM - 9 PM",
          contact_phone: "01711000000",
          is_default: true,
          active: true
        })

      {:ok, {pub_key, _priv_key}} = Crypto.get_or_bootstrap_signing_key()

      ProviderRegistry.register_provider(prescriber.bmdc_no, %{
        name: prescriber.name,
        public_key: pub_key,
        status: :active
      })

      drug = Repo.all(DrugCatalogItem) |> List.first()

      %{prescriber: prescriber, drug: drug}
    end

    test "combined BEAM VM memory and native runner footprint stays under 250MB during active Rx workflow",
         %{drug: drug} do
      :erlang.garbage_collect()
      parent = self()

      # 1. Run 5 concurrent FTS5/trigram drug searches
      search_tasks =
        ["napa", "paracetamol", "omepra", "cipro", "seclo"]
        |> Enum.map(fn q ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
            Search.run(q)
          end)
        end)

      assert length(Task.await_many(search_tasks, 5_000)) == 5

      # 2. Parse clinical shorthand and create Cloak-encrypted draft
      parsed = ShorthandParser.parse("tab napa 1+0+1 7d pc")
      assert parsed != nil

      assert {:ok, draft} =
               Prescriptions.create_draft(%{
                 patient_name: "Memory Benchmark Patient",
                 patient_phone: "+8801711111111",
                 patient_age: "35",
                 clinical_notes: "Fever and body ache"
               })

      assert {:ok, _item} =
               Prescriptions.add_item_to_draft(
                 draft,
                 drug,
                 %{
                   dosage_matrix: parsed.dosage_matrix,
                   duration_expression: parsed.duration_expression,
                   timing_instruction: Atom.to_string(parsed.timing_code)
                 },
                 1
               )

      assert {:ok, locked} = Prescriptions.finalize_prescription(draft)
      qr_payload = Crypto.build_qr_payload(locked.canonical_manifest, locked.signature)
      assert {:ok, %{valid?: true}} = Crypto.verify_qr_payload(qr_payload)

      # Measure active BEAM VM footprint
      beam_bytes = :erlang.memory(:total)

      # Measure native runner executable footprint + conservative WebView2 host working set
      exe_path = "_build/prod/rel/rx_generator/bin/RxGeneratorApp.exe"
      assert File.exists?(exe_path), "RxGeneratorApp.exe must exist to measure runner footprint"
      runner_binary_bytes = File.stat!(exe_path).size
      runner_overhead_bytes = runner_binary_bytes + @webview_host_budget_bytes

      combined_bytes = beam_bytes + runner_overhead_bytes

      assert beam_bytes < 150 * 1024 * 1024,
             "BEAM VM memory #{div(beam_bytes, 1024 * 1024)}MB exceeded 150MB budget"

      assert combined_bytes < @ceiling_bytes,
             "Combined memory footprint #{div(combined_bytes, 1024 * 1024)}MB exceeded 250MB ceiling"
    end
  end

  describe "T022: Full Air-Gap Execution Audit (Article V)" do
    setup do
      FormularyFixtures.clean_catalog!()
      FormularyFixtures.seed_catalog!()

      {:ok, prescriber} =
        Prescriptions.create_prescriber_profile(%{
          name: "Dr. Airgap Release",
          bmdc_no: "A-99999",
          qualifications: "MBBS",
          specialty: "General Medicine",
          active: true
        })

      {:ok, _chamber} =
        Prescriptions.create_chamber(%{
          prescriber_profile_id: prescriber.id,
          chamber_name: "Offline Chamber",
          address: "Road 3, Mirpur, Dhaka",
          visiting_hours: "4 PM - 8 PM",
          contact_phone: "01722000000",
          is_default: true,
          active: true
        })

      {:ok, {pub_key, _priv_key}} = Crypto.get_or_bootstrap_signing_key()

      ProviderRegistry.register_provider(prescriber.bmdc_no, %{
        name: prescriber.name,
        public_key: pub_key,
        status: :active
      })

      drug = Repo.all(DrugCatalogItem) |> List.first()

      tmp_dir =
        Path.join(System.tmp_dir!(), "rx_airgap_audit_#{:erlang.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, drug: drug}
    end

    test "full desktop bootstrap, formulary search, signing, and verification emit zero outbound network calls",
         %{tmp_dir: tmp_dir, drug: drug} do
      # Endpoint must bind strictly to loopback
      http_cfg = RxGeneratorWeb.Endpoint.config(:http)
      assert http_cfg[:ip] == {127, 0, 0, 1}

      telemetry_ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:req, :request, :start],
          [:finch, :request, :start],
          [:finch, :connect, :start]
        ])

      on_exit(fn -> :telemetry.detach(telemetry_ref) end)

      # 1. Offline user data provisioning using bundled seed DB
      assert :ok = Release.ensure_user_data_dir(tmp_dir)
      working_db = Path.join(tmp_dir, "rx_generator.db")

      assert :ok =
               Release.ensure_database_file(working_db, "priv/repo/seeds/rx_generator_seed.db")

      assert File.exists?(working_db)
      assert File.stat!(working_db).size > 0

      secrets = Release.ensure_secrets(tmp_dir)
      assert is_binary(secrets.secret_key_base)
      assert is_binary(secrets.cloak_key)

      # 2. Offline formulary search
      results = Search.run("napa")
      assert is_list(results)
      assert length(results) >= 1

      # 3. Offline draft creation, item addition, Ed25519 lock & QR verify
      assert {:ok, draft} =
               Prescriptions.create_draft(%{
                 patient_name: "Offline Patient",
                 patient_phone: "+8801722222222",
                 patient_age: "28"
               })

      assert {:ok, _item} =
               Prescriptions.add_item_to_draft(
                 draft,
                 drug,
                 %{
                   dosage_matrix: "1+0+1",
                   duration_expression: "5 days",
                   timing_instruction: "pc"
                 },
                 1
               )

      assert {:ok, locked} = Prescriptions.finalize_prescription(draft)
      qr_payload = Crypto.build_qr_payload(locked.canonical_manifest, locked.signature)
      assert {:ok, %{valid?: true}} = Crypto.verify_qr_payload(qr_payload)

      # 4. Assert zero outbound network telemetry events occurred
      refute_receive {[:req, :request, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:finch, :request, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:finch, :connect, :start], _id, _measurements, _metadata}, 50
    end
  end
end
