defmodule RxGenerator.Printing.SpoolerTest do
  use ExUnit.Case, async: true
  import Mox

  alias RxGenerator.Prescriptions.Prescription
  alias RxGenerator.Printing.Spooler

  setup :verify_on_exit!

  describe "RxGenerator.Printing.Spooler delegation (T024)" do
    test "spool/2 delegates to configured adapter when prescription is locked with signature" do
      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-20261014-TEST",
        prescriber_bmdc_no: "A-12345",
        state: :locked,
        canonical_manifest: "v1|RX-20261014-TEST|A-12345|1760424000|item1",
        signature: "base64edsig=="
      }

      RxGenerator.Printing.MockSpooler
      |> expect(:spool, 1, fn passed_rx, opts ->
        # Assert invariant attributes rather than literal pinned struct
        assert passed_rx.id == rx.id
        assert passed_rx.state == :locked
        assert opts[:copies] == 2
        :ok
      end)

      assert :ok = Spooler.spool(rx, copies: 2)
    end

    test "spool/2 strictly REJECTS draft prescription from reaching adapter (Article IX Gate)" do
      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-20261014-DRAFT",
        prescriber_bmdc_no: "A-12345",
        state: :draft
      }

      # Invariant: Spooler adapter MUST NOT be invoked on unfinalized records
      # Mox verify_on_exit! ensures no unexpected calls to MockSpooler occur

      assert {:error, :unfinalized_prescription} = Spooler.spool(rx, copies: 1)
    end

    test "spool/2 enforces safe bounds on copy count" do
      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-20261014-BOUNDS",
        prescriber_bmdc_no: "A-12345",
        state: :locked,
        canonical_manifest: "valid_manifest",
        signature: "valid_sig"
      }

      # Negative or zero copies
      assert {:error, :invalid_copy_count} = Spooler.spool(rx, copies: 0)
      assert {:error, :invalid_copy_count} = Spooler.spool(rx, copies: -1)

      # Excessive copy volume (paper runaway protection)
      assert {:error, :invalid_copy_count} = Spooler.spool(rx, copies: 100)
    end

    test "spool/2 propagates adapter error tuples" do
      rx = %Prescription{
        id: Ash.UUID.generate(),
        rx_number: "RX-20261014-FAIL",
        prescriber_bmdc_no: "A-12345",
        state: :locked,
        canonical_manifest: "valid_manifest",
        signature: "valid_sig"
      }

      RxGenerator.Printing.MockSpooler
      |> expect(:spool, 1, fn _rx, _opts -> {:error, :out_of_paper} end)

      assert {:error, :out_of_paper} = Spooler.spool(rx, [])
    end
  end
end
