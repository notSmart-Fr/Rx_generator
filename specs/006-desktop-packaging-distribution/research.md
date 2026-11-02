# Phase 0 Research: Desktop Packaging, Dynamic Port IPC, and SQLite Bootstrapping

## Overview & Architecture

RxGenerator is designed as an edge-native, air-gapped clinical prescription system. Packaging it as a desktop application requires:
1. **Self-Contained Mix Release**:
   - `include_erts: true` to bundle Erlang/OTP erts runtime.
   - Bundling precompiled SQLite NIF (`exqlite`), cryptographic Ed25519 primitives, static Phoenix assets, and vector model embeddings.
2. **Dynamic Loopback Port & IPC**:
   - Phoenix/Bandit must bind exclusively to `127.0.0.1` on a dynamically selected port (or scan available ephemeral ports starting from 4000).
   - Once the listener starts, an OTP lifecycle hook / endpoint listener emits an IPC signal via standard output: `[RX_PORT:<port>]`.
3. **Native Desktop Window Wrapper**:
   - A lightweight OS process (C# / .NET WinForms with WebView2 on Windows; WebKitGTK / shell wrapper on Linux) that:
     - Enforces single-instance execution via a named mutex (`RxGenerator_SingleInstance_Mutex`).
     - Spawns the BEAM release as a child subprocess with piped stdin/stdout.
     - Reads stdout line-by-line until encountering `[RX_PORT:<port>]`.
     - Directs the embedded webview to `http://127.0.0.1:<port>`.
     - Supervises the child process: closing the native window terminates the child process cleanly; child process crash surfaces an error dialog and exits.
4. **Offline Database & Encryption Key Bootstrapping**:
   - On release boot (`RxGenerator.Release.bootstrap/0` or application start), the system resolves the OS user data directory:
     - Windows: `%APPDATA%\RxGenerator`
     - Linux: `$XDG_DATA_HOME/rx_generator` or `~/.local/share/rx_generator`
   - If `rx_generator.db` does not exist in the user data directory:
     - Atomically copies the pre-seeded catalog database template (`priv/repo/seeds/rx_generator_seed.db` or bundled SQLite snapshot) into the user directory.
   - If `secret_key_base` or `cloak_key` are not in environment variables, a machine-local persistent secrets file (`secrets.env` or encrypted key) is generated in the user data directory.
   - Auto-runs any pending Ash/Ecto migrations so future software versions seamlessly upgrade existing schemas without touching doctor identity or patient vaults.
5. **Print Spooler Integration**:
   - The native webview allows JavaScript `window.print()` to route directly to the OS print dialog.
   - `@media print` CSS enforces High Court bold generic names, clean two-column chamber headers, and suppresses browser URL headers/footers.

---

## Technical Feasibility & Prototype Details

### 1. Loopback Port Discovery & Bandit Configuration
In Phoenix with Bandit, setting the port to `0` allows the operating system kernel to allocate an ephemeral free port:
```elixir
# lib/rx_generator_web/endpoint.ex
def init(:supervisor, config) do
  port =
    case System.get_env("PORT") do
      nil -> 0 # Ephemeral dynamic port
      "0" -> 0
      val -> String.to_integer(val)
    end
  {:ok, Keyword.put(config, :http, [ip: {127, 0, 0, 1}, port: port])}
end
```
After the endpoint boots, its listening port is retrieved via:
```elixir
{:ok, {_ip, actual_port}} = ThousandIsland.Server.listener_info(RxGeneratorWeb.Endpoint.HTTP)
# or via Phoenix endpoint server info
IO.puts("[RX_PORT:#{actual_port}]")
```
Alternatively, an Elixir port scanner module can find the first open port starting from `4000` on `127.0.0.1` and pass it directly to `Bandit`.

### 2. Native Windows Runner (WebView2)
Windows 10 (20H2+) and Windows 11 include Microsoft Edge WebView2 runtime built-in.
A compiled standalone C# application (`RxGeneratorApp.exe`) can be compiled using the built-in .NET Framework compiler (`csc.exe`) without needing Visual Studio or external toolchains:
- Footprint: < 500 KB executable.
- Uses `System.Threading.Mutex` for single instance.
- Spawns `rel\rx_generator\bin\rx_generator.bat start` with `RedirectStandardOutput = true`.
- Employs a Windows Job Object (`SetInformationJobObject` with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`) to guarantee that if `RxGeneratorApp.exe` is killed or closed, Windows kernel automatically terminates the child BEAM processes immediately.
- Hosts `Microsoft.Web.WebView2.WinForms.WebView2`.

### 3. Native Linux Runner (WebKitGTK / Shell)
On Linux:
- Packaged as a `.deb` package with `usr/lib/rx_generator` and a `/usr/bin/rx_generator` launcher.
- Uses a lightweight WebKitGTK launcher or Python/GTK / C webview wrapper that launches the release and connects to the port.

### 4. Database Bootstrapping (`RxGenerator.Release`)
An operational module `RxGenerator.Release` executes before the endpoint starts:
```elixir
defmodule RxGenerator.Release do
  @app :rx_generator

  def bootstrap do
    ensure_user_data_dir()
    ensure_database_file()
    ensure_secrets()
    run_migrations()
  end
end
```

---

## Constitution Compliance Check
- **Article I (Zero Hallucination)**: Satisfied. Pre-seeded DGDA database is bundled directly.
- **Article II (High Court Generic Mandate)**: Satisfied. `@media print` rules enforce bold uppercase molecule names on native printer spooler output.
- **Article V (Zero-Cloud Edge Autonomy)**: Satisfied. 100% self-contained ERTS release with bundled database, zero external internet or cloud calls.
- **Article VI (Memory Ceiling < 250MB RAM)**: Satisfied. BEAM node (~70-90MB) + native webview (~60-80MB) totals ~150-170MB RAM, well below the 250MB limit.
- **Article VIII (Encryption at Rest)**: Satisfied. Cloak encryption key is persistently generated and isolated in the user data directory.

