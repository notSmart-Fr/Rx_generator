# IPC Protocol & Lifecycle Contract: Desktop Wrapper <-> BEAM Subprocess

## 1. Process Supervision & Signaling

### Subprocess Invocation
- The **Parent Process** (`RxGeneratorApp.exe` on Windows or `rx_generator_runner` on Linux) executes:
  - Windows: `bin\rx_generator.bat start` (or embedded ERTS command `erts\bin\erl.exe ...`) with standard input and standard output redirected.
  - Linux: `bin/rx_generator start` with piped stdout/stdin.
- The parent wrapper places the child process into an OS Job Object (`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`) on Windows or sends `SIGTERM` / `SIGQUIT` on Linux on window closure.

### Port Ready Signal (BEAM -> Native Wrapper)
- When the Phoenix endpoint is bound and ready to accept HTTP/WebSocket connections, BEAM writes a single line to `stdout`:
  ```
  [RX_PORT:<INTEGER_PORT>]
  ```
  - Example: `[RX_PORT:49152]`
- **Timeout**: The wrapper waits up to 10 seconds for `[RX_PORT:<INTEGER_PORT>]`. If not received, the wrapper surfaces an error dialog containing the trailing 20 lines of child stderr/stdout.

### Webview Navigation
- Upon parsing `[RX_PORT:<PORT>]`, the webview navigates to:
  ```
  http://127.0.0.1:<PORT>/
  ```

---

## 2. Print Spooler Contract (Frontend -> OS Spooler)

### Action Trigger
- Triggered either via:
  - User clicking the "Print Prescription" button (`phx-click="print"`).
  - Keyboard shortcut: `Ctrl+P` / `Cmd+P`.
- The LiveView executes a client hook:
  ```javascript
  window.print();
  ```

### WebView Print Behavior
- The native webview intercepts `window.print()` and opens the native OS printer selection and configuration dialog.
- The print layout adheres to `@media print` rules:
  - `@page { margin: 10mm; size: auto; }`
  - Suppresses browser header (URL, page title) and footer (date, URL).
  - High Court generic typography in bold uppercase.
  - Two-column chamber header and patient demographics.
  - Crisp high-contrast 2D Ed25519 QR barcode.

---

## 3. Single Instance IPC Contract

- The native wrapper acquires a named system mutex:
  - Windows: `Global\RxGenerator_SingleInstance_App_Mutex`
  - Linux: Advisory file lock on `/tmp/rx_generator.lock`
- If mutex acquisition fails:
  - Find existing window handle (`FindWindow` with title `RxGenerator`).
  - Bring existing window to front (`SetForegroundWindow`).
  - Exit new process with status code `0`.

