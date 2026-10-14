# Contract: Print Spooler Behaviour & UI Event Protocols

**Feature Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14

## 1. Backend Spooler Behaviour Contract

```elixir
defmodule RxGenerator.Printing.Spooler do
  @moduledoc """
  Hardware interface behaviour for dispatching finalized prescriptions to physical or virtual print spoolers.
  """

  alias RxGenerator.Prescriptions.Prescription

  @type spool_opt :: {:copies, pos_integer()} | {:printer_name, String.t()} | {:duplex, boolean()}
  @type spool_result :: :ok | {:error, reason :: term()}

  @callback spool(prescription :: Prescription.t(), opts :: [spool_opt()]) :: spool_result()
end
```

### Configured Adapters

- **Production Driver**: `RxGenerator.Printing.OSSpooler`
  - Interfaces with native operating system printing queues (e.g. `lpr` / `lp` on Linux/macOS, or PowerShell spooler on Windows).
- **Test Double (Mox)**: `RxGenerator.Printing.MockSpooler`
  - Defined in `test/support/mocks.ex` using `Mox.defmock/2`.
  - Configured via Application environment:
    ```elixir
    # config/test.exs
    config :rx_generator, :print_spooler, RxGenerator.Printing.MockSpooler

    # config/config.exs
    config :rx_generator, :print_spooler, RxGenerator.Printing.OSSpooler
    ```

---

## 2. LiveView Socket Event Protocol

### Client → Server Events

| Event Name | Parameters | Precondition | State Transition / Outcome |
|:---|:---|:---|:---|
| `"finalize_prescription"` | `%{}` | Draft prescription with `length(items) > 0` | Transitions prescription to `:locked`, compiles manifest, signs via Ed25519, generates QR SVG, assigns to socket. |
| `"trigger_print"` | `%{}` | Prescription is `:locked` | Emits server-side spooler dispatch (if headless) AND pushes `"print_prescription"` event to client. |
| `"trigger_reprint"` | `%{}` | Prescription is `:locked` | Re-dispatches without modifying signature or manifest. |

### Server → Client Pushed Events

| Pushed Event | Payload | Client Action |
|:---|:---|:---|
| `"print_prescription"` | `%{}` | Client JS hook invokes `window.print()`. Clean `@media print` CSS formats paper view. |
| `"prescription_finalized"` | `%{rx_number: String.t()}` | Client focuses print trigger button or displays finalized toast. |

---

## 3. High Court Print Layout CSS Rules

```css
@media print {
  /* Suppress all interactive HUD controls, omnibar, search results, and layout bars */
  #prescription-omnibar,
  header,
  nav,
  .print\:hidden {
    display: none !important;
  }

  /* Ensure prescription canvas expands to full paper width without shadows or margins */
  #prescription-canvas {
    box-shadow: none !important;
    border: none !important;
    max-width: 100% !important;
    padding: 0 !important;
    margin: 0 !important;
    width: 100% !important;
  }

  /* Enforce bold uppercase generics (equal or greater prominence than brand name) */
  .generic-name-print {
    font-size: 1.25rem !important;
    font-weight: 900 !important;
    text-transform: uppercase !important;
    color: black !important;
  }

  .brand-name-print {
    font-size: 0.95rem !important;
    font-weight: 600 !important;
    color: #333 !important;
  }

  /* Force page breaks to avoid splitting a medication block across pages */
  .rx-item-row {
    break-inside: avoid;
    page-break-inside: avoid;
  }
}
```
