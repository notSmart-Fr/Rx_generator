# Feature Specification: 006 Desktop Packaging & Distribution

**Feature Branch**: `006-desktop-packaging-distribution`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "Package RxGenerator as a self-contained, air-gapped desktop application (.exe / .deb) with zero prerequisite runtime dependencies (no separate Elixir, Erlang, or Node installations required). Bundle the compiled BEAM release, pre-seeded SQLite formulary database, and local vector index within a native webview window wrapper. Ensure automatic local port management, graceful background process termination on window close, and seamless binding to the native OS print spooler."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Self-Contained Desktop Launch & Lifecycle (Priority: P1)

As a clinical practitioner in an off-grid or rural health center,
I want to launch RxGenerator directly from an executable binary (.exe or .deb installer/bundle) without installing Erlang, Elixir, Node.js, or administering a local web server,
So that I can immediately start prescribing on standard commodity PC hardware without technical setup or IT overhead.

**Why this priority**:
Zero runtime installation friction is the foundational requirement for edge-native deployment in rural clinics. If the app cannot cold-boot and manage its own runtime lifecycle out-of-the-box, no other clinical feature is accessible to doctors.

**Independent Test**:
Can be fully tested by launching the packaged desktop executable on a clean target machine (or clean VM/sandbox lacking Elixir/Node/Erlang), verifying that the native window opens with the prescription interface ready, and verifying that closing the window terminates all underlying BEAM background processes.

**Acceptance Scenarios**:
1. **Given** a host environment without Elixir, Erlang, or Node.js installed,
   **When** the user executes the packaged application binary,
   **Then** a native desktop window opens within 3 seconds displaying the RxGenerator interface with zero runtime missing errors.
2. **Given** the packaged desktop application is running,
   **When** the user closes the native application window (or presses Alt+F4 / clicks close),
   **Then** the native wrapper sends a shutdown signal to the underlying BEAM release process, ensuring no orphaned background processes or locked database files remain.
3. **Given** another process is already occupying default port `4000`,
   **When** RxGenerator desktop boots,
   **Then** it dynamically discovers an available local loopback port, binds the Phoenix/Bandit server to `127.0.0.1:<allocated_port>`, and directs the native webview to that port without manual user configuration.

---

### User Story 2 - Pre-Seeded Offline Storage & Index Initialization (Priority: P2)

As a visiting clinic doctor without internet access,
I want the packaged desktop app to initialize with pre-seeded DGDA formulary data and pre-compiled local vector/FTS5 indexes on first boot,
So that I can immediately perform instant medicine search and interaction checks completely air-gapped without needing an initial download or setup step.

**Why this priority**:
In accordance with Article V (Zero-Cloud Edge Autonomy) and Article VII (Two-Tier Entity Resolution), the offline prescription engine requires its DGDA drug catalog and vector artifacts bundled directly in the distribution.

**Independent Test**:
Run the desktop release on an air-gapped environment (network interfaces disabled); perform a drug search query in the omnibar on the first boot; verify search results resolve in <15ms with full generic molecule names.

**Acceptance Scenarios**:
1. **Given** an air-gapped machine with zero network connectivity on first launch,
   **When** the application starts for the first time,
   **Then** it automatically extracts/initializes the SQLite database containing the full DGDA catalog and AshCloak cryptographic tables in the OS user data directory (e.g. `%APPDATA%/RxGenerator` or `~/.config/rx_generator`).
2. **Given** the app has established its user data directory,
   **When** subsequent updates or restarts occur,
   **Then** existing prescriber profiles, chamber configs, and patient vault records are preserved without overwriting existing physician data.

---

### User Story 3 - Native OS Print Spooler Integration (Priority: P3)

As a prescribing physician,
I want to print prescription sheets directly to the local clinic printer via the native OS print spooler with zero browser UI chrome or margins corruption,
So that printed prescriptions strictly comply with the High Court generic mandate and chamber formatting guidelines.

**Why this priority**:
Prescription delivery requires reliable physical output. Clinical printers in rural setups vary across USB thermal, dot-matrix, and inkjets; the webview must seamlessly bridge JavaScript `window.print()` triggers to the OS native printing dialog/spooler.

**Independent Test**:
Trigger the print action from the LiveView UI within the native window; verify the OS native print dialog opens with `@media print` styles applied (2-column chamber header, bold generic molecule names, 2D QR barcode seal).

**Acceptance Scenarios**:
1. **Given** a finalized prescription within the desktop webview,
   **When** the user clicks the "Print Prescription" action or presses `Ctrl+P`,
   **Then** the native webview invokes the OS print subsystem with 0 header/footer browser URL metadata, cleanly rendering the high-court compliant canvas layout.
2. **Given** a thermal or letterhead paper setup configured in the OS,
   **When** printing is submitted,
   **Then** the spooler receives the document without truncation of the Ed25519 QR seal.

---

### Edge Cases

- **Port Collision**: If port 4000 (or any predefined port) is occupied by an external service, the app automatically selects an ephemeral port (`port: 0` or port scan) on `127.0.0.1` and points the webview wrapper to the actual listening socket.
- **Unexpected Process Termination (SIGKILL / Power Outage)**: The SQLite database runs in WAL mode (`journal_mode=WAL`) so that abrupt system shutdowns do not corrupt prescription vaults or catalogs.
- **Multiple Instances Prevention**: If the user clicks the desktop icon while an instance is already running, the secondary instance focuses the existing window rather than spawning conflicting BEAM nodes or SQLite locks.
- **Read-Only App Directory**: When packaged as an installer or installed into `Program Files` or `/opt/`, the application must write dynamic databases, logs, and vault state to the user data directory (`%APPDATA%` on Windows, `$XDG_DATA_HOME` on Linux), never attempting to write to the read-only application bundle directory.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST package the complete BEAM runtime (Erlang/OTP + Elixir compiled release) with all NIFs (e.g. SQLite3, Ed25519 crypto) bundled so zero external software installation is required on the client machine.
- **FR-002**: System MUST include a native desktop window wrapper (utilizing native OS Webview, e.g. WebView2 on Windows, WebKitGTK on Linux) that displays the Phoenix LiveView application as a native desktop window without exposing a standard browser navigation bar or URL bar.
- **FR-003**: System MUST bind the HTTP endpoint exclusively to the local loopback interface (`127.0.0.1`) with dynamic port allocation or collision handling, preventing exposure to the local area network.
- **FR-004**: System MUST bundle the pre-seeded DGDA formulary database and ensure that on initial run, the working database is provisioned in the standard OS user data directory.
- **FR-005**: System MUST bundle local vector model files / embedding weights within the release bundle so Tier 2 neural fallback functions completely air-gapped.
- **FR-006**: System MUST ensure bidirectional lifecycle synchronization: closing the native window MUST cleanly terminate the BEAM release, and a crash of the BEAM release MUST display an informative diagnostic dialog before exiting.
- **FR-007**: System MUST enforce single-instance execution per user session using a named mutex or lockfile, focusing the existing active window upon duplicate launch attempts.
- **FR-008**: System MUST pass window print triggers (`window.print()`) directly to the native host OS print subsystem, ensuring proper paper selection and suppression of browser headers/footers.
- **FR-009**: Packaging configuration MUST produce standalone distribution artifacts: an executable / installer for Windows (`.exe` / `.msi`) and a package for Linux (`.deb` / AppImage).
- **FR-010**: System MUST automatically generate and securely store a persistent unique node secret key base and encryption key during first-run initialization if not already set, keeping the cryptographic patient vault secure per machine.

### Key Entities

- **Desktop Release Bundle**: The compiled, standalone artifact containing the Erlang runtime system (ERTS), compiled BEAM modules, static assets, and native NIF shared libraries.
- **Native Window Wrapper**: The lightweight OS process that hosts the webview control, launches and supervises the BEAM release subprocess, monitors port readiness, and handles OS window events.
- **User Data Store**: The directory located in the OS-standard app data path (`%APPDATA%/RxGenerator` or `~/.local/share/rx_generator`) holding the user's SQLite database (`rx_generator.db`), logs, and local configuration.
- **Distribution Manifest**: Metadata specifying the release version, target architecture (x86_64), build dependencies, and asset inclusions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero runtime prerequisites: A virgin Windows 10/11 or Ubuntu 22.04+ machine without Erlang, Elixir, Node.js, or Git installed can run the application directly from the distributed installer/executable.
- **SC-002**: Cold boot to interactive LiveView window occurs in under 3.5 seconds on commodity dual-core PC hardware with 4GB RAM.
- **SC-003**: 100% clean termination: After closing the desktop window, `rx_generator` BEAM and webview processes occupy 0 CPU and 0 MB RAM (zero orphaned processes in Task Manager / `ps aux`).
- **SC-004**: Memory footprint of the entire desktop package (BEAM node + native webview combined) remains under 250MB RAM during standard prescription drafting, strictly satisfying Article VI of the Constitution.
- **SC-005**: 100% offline air-gap fidelity: The application builds, installs, launches, queries drugs, signs prescriptions, and prints with network adapters physically disabled.
- **SC-006**: Single-instance guarantee: Launching a secondary instance activates the current window in under 500ms without port conflict or database lock errors.

## Clarifications & Architectural Decisions

### Session 2026-11-02 Clarifications
- **Q1: Desktop Shell / Wrapper Architecture**:
  - *Decision*: Native Webview Wrapper via a lightweight native runner (WebView2 on Windows / WebKitGTK on Linux). The wrapper binary acts as the parent OS process, supervising the compiled OTP release child process directly via stdin/stdout pipe and OS process handles, keeping RAM overhead minimal (<30MB for the wrapper shell).
- **Q2: Loopback Port Management & Collision Avoidance**:
  - *Decision*: Automatic dynamic port allocation on `127.0.0.1`. Bandit / Phoenix dynamically discovers an available loopback port (or binds with port `0` / scans from 4000) and communicates the bound port directly to the native wrapper via stdout IPC message (e.g. `[RX_PORT:41234]`) before the webview navigates, eliminating port conflict errors.
- **Q3: Pre-seeded Database & User Data Management**:
  - *Decision*: A pre-seeded template database is bundled in the release assets. On initial boot, the app checks the OS user profile (`%APPDATA%/RxGenerator/rx_generator.db` on Windows or `~/.local/share/rx_generator/rx_generator.db` on Linux). If absent, the template is atomically copied; if present, standard Ecto/Ash migrations run automatically on startup to ensure forward schema compatibility without touching existing doctor profiles or patient records.
- **Q4: Native OS Print Spooler Integration**:
  - *Decision*: Native OS print dialog triggered directly via standard `window.print()` hooked to the native webview print pipeline. Styled with `@media print` rules enforcing High Court generic molecule bold uppercase typography, two-column chamber headers, suppression of browser chrome/footers, and crisp 2D QR code barcode rendering.

## Assumptions

- Target operating systems are modern 64-bit platforms: Windows 10/11 (with Microsoft Edge WebView2 runtime, standard on Windows 10 20H2+ and Windows 11) and modern Linux distributions (Debian/Ubuntu with WebKitGTK).
- The packaging strategy leverages Mix Releases with ERTS inclusion (`include_erts: true`) paired with a lightweight native webview wrapper or desktop runner (such as `Desktop` / `Webview` / `Tauri` / Go-based webview runner or equivalent Elixir-native desktop launcher) compliant with Article V and Article VI.
- The user's prescription data and cryptographic keys will persist in the standard OS user profile directory across app updates.

