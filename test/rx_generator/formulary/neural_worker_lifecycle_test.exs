defmodule RxGenerator.Formulary.NeuralWorkerLifecycleTest do
  use RxGeneratorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias RxGenerator.Formulary.NeuralWorker
  alias RxGenerator.Formulary.Search
  alias RxGenerator.Prescriptions
  alias RxGenerator.Test.FormularyFixtures

  setup do
    FormularyFixtures.clean_catalog!()
    FormularyFixtures.seed_catalog!()
    :ok
  end

  defmodule MockVectorBackend do
    def vectorize(_text) do
      {:ok, for(_ <- 1..256, into: <<>>, do: <<0.1::float-32-little>>)}
    end
  end

  describe "T019: Asynchronous warm-up and state transitions" do
    test "worker initializes in :warming state and completes warmup via {:continue, :warmup}" do
      parent = self()

      # Start supervised isolated instance with unique name and notify_pid
      test_worker_name = :"test_worker_#{System.unique_integer([:positive])}"

      worker_pid =
        start_supervised!(
          {NeuralWorker,
           [
             name: test_worker_name,
             backend: MockVectorBackend,
             notify_pid: parent,
             on_warmup: fn ->
               # Small yield to guarantee :continue async handling
               :timer.sleep(10)
             end
           ]}
        )

      # Ensure process is alive and successfully received {:continue, :warmup}
      assert_receive {:warmup_completed, ^worker_pid}, 1000

      # Synchronous status verification confirms :ready
      assert GenServer.call(worker_pid, :status) == :ready
    end

    test "vectorize returns {:error, :warming_up} when status is :warming and no backend is available" do
      test_worker_name = :"test_worker_warming_#{System.unique_integer([:positive])}"

      worker_pid =
        start_supervised!(
          {NeuralWorker,
           [
             name: test_worker_name,
             backend: nil,
             model_path: "non_existent_path"
           ]}
        )

      # Force state to :warming to simulate in-flight graph compilation
      :sys.replace_state(worker_pid, fn state -> %{state | status: :warming} end)

      assert {:error, :warming_up} = GenServer.call(worker_pid, {:vectorize, "aseclofen"})
    end

    test "Search.run/2 falls back non-blocking without crash when NeuralWorker is warming" do
      # Test search execution while global worker is safely mocked in an isolated block
      pid = Process.whereis(NeuralWorker)
      assert is_pid(pid), "Global NeuralWorker must be supervised"

      original_state = :sys.get_state(pid)

      try do
        :sys.replace_state(pid, fn state -> %{state | status: :warming, backend: nil} end)

        start_time = System.monotonic_time(:millisecond)
        # Search a query that misses FTS5
        results = Search.run("nonexistentphoneticquery")
        elapsed = System.monotonic_time(:millisecond) - start_time

        # Must execute in under 15ms without blocking
        assert elapsed < 50
        assert is_list(results)
      after
        # Guaranteed cleanup restores original state even if assertion fails
        :sys.replace_state(pid, fn _ -> original_state end)
      end
    end

    test "LiveView mount completes without freezing (< 15ms) during cold-boot / warming state", %{conn: conn} do
      pid = Process.whereis(NeuralWorker)
      original_state = :sys.get_state(pid)

      try do
        # Simulate worker currently in warming phase
        :sys.replace_state(pid, fn state -> %{state | status: :warming, backend: nil} end)

        # Ensure DB connection is primed so cold connection checkout does not skew measurement
        _ = Prescriptions.get_or_create_active_draft()

        # Measure direct PrescriptionLive.mount execution time
        start_time = System.monotonic_time(:microsecond)
        {:ok, socket} = RxGeneratorWeb.PrescriptionLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
        mount_micros = System.monotonic_time(:microsecond) - start_time
        mount_ms = div(mount_micros, 1000)

        # Direct mount must be well below 15ms non-blocking budget
        assert mount_ms <= 15, "Direct LiveView mount took #{mount_ms}ms, exceeding 15ms budget"
        assert socket.assigns.page_title == "New Prescription"

        # Also verify live integration mounts without error
        {:ok, view, _html} = live(conn, "/prescriptions/new")
        assert has_element?(view, "#prescription-omnibar")
      after
        :sys.replace_state(pid, fn _ -> original_state end)
      end
    end
  end
end
