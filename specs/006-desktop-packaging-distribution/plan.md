# Implementation Plan: 006 Desktop Packaging & Distribution

**Branch**: `006-desktop-packaging-distribution` | **Date**: 2026-11-02 | **Spec**: [spec.md](file:///d:/Rx_generator/specs/006-desktop-packaging-distribution/spec.md)

**Input**: Feature specification from `/specs/006-desktop-packaging-distribution/spec.md`

## Summary

Package `RxGenerator` as an edge-native, self-contained desktop application with zero runtime prerequisites on the client machine. The solution bundles a fully compiled Erlang/Elixir BEAM release (with ERTS included) alongside pre-seeded DGDA SQLite database snapshots and vector models. A lightweight native OS wrapper (WebView2 on Windows / WebKitGTK on Linux) supervises the BEAM node as a child process. The BEAM node dynamically binds Phoenix/Bandit to an ephemeral loopback port (`127.0.0.1`), emits a standard-output IPC readiness message (`[RX_PORT:<port>]`), and navigates the native webview. The native wrapper guarantees single-instance execution, catches `window.print()` triggers for native OS print spooler output, and guarantees clean termination of all child processes on window exit, strictly maintaining total RAM usage under 250MB.

## Technical Context

**Language/Version**: Elixir 1.17+ / Erlang OTP 27+, C# (.NET Framework 4.8 / WebView2 for Windows wrapper), CSS3 `@media print`.

**Primary Dependencies**: `mix release`, `Bandit`, `AshSqlite` / `EctoSqlite3`, `AshCloak`, `Phoenix.LiveView`.

**Storage**: SQLite3 with WAL mode in `%APPDATA%/RxGenerator/rx_generator.db` (Windows) or `~/.local/share/rx_generator/rx_generator.db` (Linux). Seed database template bundled in release `priv/repo/seeds/rx_generator_seed.db`.

**Testing**: `ExUnit`, `Phoenix.LiveViewTest`, behavioral test for release bootstrap and dynamic port discovery.

**Target Platform**: Windows 10/11 x86_64, Linux x86_64 (Debian/Ubuntu).

**Project Type**: Desktop Application (Self-Contained BEAM Release + Native OS WebView Supervisor).

**Performance Goals**: Cold-boot to interactive LiveView window in < 3.5 seconds; < 15ms autocomplete round-trip; total RAM footprint < 250MB (BEAM + WebView combined).

**Constraints**: Completely air-gapped (Article V); zero external cloud dependencies; clean process termination on window close; zero SQLite corruption on abrupt exit (WAL mode).

**Scale/Scope**: Single clinician workstation per instance; local high-throughput prescription generation.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Requirement | Status / Compliance Strategy |
| :--- | :--- | :--- |
| **Article I** | Zero Hallucination Boundary | **PASS**: Pre-seeded DGDA SQLite database bundled into release assets. No external APIs. |
| **Article II** | High Court Generic Mandate | **PASS**: `@media print` CSS ensures bold uppercase generic molecule rendering on native printer output. |
| **Article III** | Human-in-the-Loop Absolute | **PASS**: Clinical validation gates and prescriber review unmodified. |
| **Article V** | Zero-Cloud Edge Autonomy | **PASS**: Self-contained ERTS release with bundled NIFs, database, and assets. 100% offline air-gap fidelity. |
| **Article VI** | Memory Ceiling < 250MB RAM | **PASS**: BEAM node (~80MB) + native webview (~70MB) = ~150MB total RAM, comfortably within 250MB ceiling. |
| **Article VII** | Two-Tier Entity Resolution | **PASS**: Tier 1 FTS5 and Tier 2 Nx/Bumblebee vector embeddings bundled in release. |
| **Article VIII**| Encryption-at-Rest for PHI | **PASS**: AES-256-GCM Cloak key persistently generated and secured in OS user profile directory. |
| **Article X** | Offline Ed25519 Signing | **PASS**: Ed25519 detached signatures printed in high-contrast 2D QR code via native spooler. |

## Project Structure

### Documentation (this feature)

```text
specs/006-desktop-packaging-distribution/
├── plan.md              # This file
├── research.md          # Technical research & prototype analysis
├── data-model.md        # User data layout & lifecycle state machine
├── quickstart.md        # Build, package, and distribution steps
├── contracts/
│    └── desktop-ipc-contract.md # Native wrapper <-> BEAM IPC specification
└── tasks.md             # Generated in next phase
```

### Source Code Layout

```text
lib/
├── rx_generator/
│    └── release.ex                   # Bootstrapping (data dir, seed copy, secrets, migrations)
├── rx_generator_web/
│    ├── endpoint.ex                  # Dynamic loopback port binding (127.0.0.1:0 or 4000+)
│    └── listeners/
│         └── port_notifier.ex        # Emits [RX_PORT:<port>] to stdout on endpoint startup
native_runner/
├── windows/
│    ├── RxGeneratorApp.cs            # C# WebView2 supervisor runner (Job Object, Mutex, IPC)
│    └── build_runner.ps1             # Compiles RxGeneratorApp.exe via csc.exe
└── linux/
     └── rx_generator_runner.sh       # Linux WebKitGTK / shell wrapper
rel/
├── env.bat.eex                       # Windows release environment script
├── env.sh.eex                        # Linux release environment script
└── overlays/
     └── bin/
test/
└── rx_generator/
     └── release_bootstrap_test.exs   # Tests dynamic directory provisioning and port discovery
```

## Phase Breakdown

- **Phase 0: Research & Feasibility**: (Completed in [research.md](file:///d:/Rx_generator/specs/006-desktop-packaging-distribution/research.md))
- **Phase 1: Architecture & Contracts**: (Completed in [data-model.md](file:///d:/Rx_generator/specs/006-desktop-packaging-distribution/data-model.md) & [desktop-ipc-contract.md](file:///d:/Rx_generator/specs/006-desktop-packaging-distribution/contracts/desktop-ipc-contract.md))
- **Phase 2: OTP Release Configuration**: Configure `mix.exs` releases with `include_erts: true`, custom `rel/env.bat.eex`, and asset pruning.
- **Phase 3: Database & Secret Bootstrapping**: Implement `RxGenerator.Release` for `%APPDATA%` resolution, template database seeding, persistent `secrets.env` generation, and auto-migration on boot.
- **Phase 4: Dynamic Loopback Port & IPC Signal**: Configure Bandit/Phoenix dynamic loopback port listener and emit `[RX_PORT:<port>]` to stdout on startup.
- **Phase 5: Native WebView2 Supervisor Runner**: Build lightweight single-instance Windows runner with Job Object child termination and automatic webview navigation to allocated port.
- **Phase 6: Native OS Print Spooler Verification**: Ensure `@media print` styles and `window.print()` trigger native print dialog cleanly with suppressed headers/footers.
- **Phase 7: Packaging & Automated Verification**: Verify complete standalone build, RAM ceilings, zero orphaned processes on exit, and offline execution.
