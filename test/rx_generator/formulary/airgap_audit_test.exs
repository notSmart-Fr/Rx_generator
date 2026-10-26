defmodule RxGenerator.Formulary.AirgapAuditTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.Ingestion.Vectorizer
  alias RxGenerator.Formulary.NeuralWorker
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    Mix.Tasks.Formulary.Vectorize.run(["--quiet"])
    :ok
  end

  describe "T028: Air-gapped network isolation audit (Article V)" do
    test "vector inference and Tier-2 search execute with zero outbound socket/HTTP network calls" do
      # Attach a telemetry handler to observe any outgoing HTTP / socket events if emitted by Req/Finch
      test_pid = self()

      telemetry_ref =
        :telemetry_test.attach_event_handlers(test_pid, [
          [:finch, :request, :start],
          [:finch, :connect, :start],
          [:req, :request, :start]
        ])

      # 1. Run local NeuralWorker vectorization directly
      assert {:ok, vector} = NeuralWorker.vectorize("paracetamol")
      assert is_binary(vector)
      assert byte_size(vector) == 1024

      # 2. Run Vectorizer batch embedding pipeline
      assert {:ok, batch_vectors} =
               Vectorizer.vectorize_batch([
                 "Napa (Paracetamol) Tablet",
                 "Ciprocin (Ciprofloxacin) Tablet"
               ])

      assert length(batch_vectors) == 2

      # 3. Run end-to-end Tier-2 search on severe phonetic misspelling
      results = Search.run("paracitamol", limit: 3)
      assert length(results) > 0
      top = hd(results)
      assert top.generic_name =~ "Paracetamol"

      # 4. Assert zero outbound HTTP/socket request events were emitted
      refute_receive {[:finch, :request, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:finch, :connect, :start], _id, _measurements, _metadata}, 50
      refute_receive {[:req, :request, :start], _id, _measurements, _metadata}, 50

      :telemetry.detach(telemetry_ref)
    end
  end
end
