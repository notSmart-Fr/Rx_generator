defmodule RxGenerator.Formulary.MemoryBenchmarkTest do
  use RxGenerator.DataCase, async: false

  alias RxGenerator.Formulary.Search
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    :ok
  end

  @ceiling_bytes 250 * 1024 * 1024 # 250MB

  describe "T020: Memory ceiling enforcement under concurrent autocomplete load (Article VI)" do
    test "active memory remains strictly below 250MB under 10 concurrent autocomplete requests" do
      # Baseline memory
      :erlang.garbage_collect()
      baseline_mem = :erlang.memory(:total)
      assert baseline_mem < @ceiling_bytes, "Baseline memory #{baseline_mem} already exceeds 250MB"

      queries = [
        "paracit",
        "napa 500",
        "aseclo",
        "sipro",
        "seclof cap",
        "omepra",
        "paracit syr",
        "ciprocin",
        "napa tab",
        "paracetamol"
      ]

      parent = self()

      # Run 10 concurrent autocomplete requests
      tasks =
        Enum.map(queries, fn q ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(RxGenerator.Repo, parent, self())

            for _ <- 1..5 do
              Search.run(q)
            end
          end)
        end)

      results = Task.await_many(tasks, 5000)
      assert length(results) == 10

      # Post-load memory measurement
      active_mem = :erlang.memory(:total)
      assert active_mem < @ceiling_bytes,
             "Memory usage #{div(active_mem, 1024 * 1024)}MB exceeded 250MB ceiling"
    end
  end
end
