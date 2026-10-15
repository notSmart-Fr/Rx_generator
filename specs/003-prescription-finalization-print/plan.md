# Implementation Plan: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14 (Hardened) | **Spec**: [spec.md](file:///d:/Rx_generator/specs/003-prescription-finalization-print/spec.md)

**Input**: Feature specification from `specs/003-prescription-finalization-print/spec.md`

## Summary

Implement clinical prescription finalization, offline asymmetric Ed25519 cryptographic signing, compact QR code generation, High Court-compliant print layout, and dual-dispatch OS print spooling. Once finalized via the `:lock` transition on `Prescription`, line items become permanently immutable across all action types (including destroy/soft-archival). A compact, byte-deterministic manifest sorted by `display_order ASC, then id ASC` (with delimiter sanitization and 8-character drug catalog prefixes) is signed using Erlang's native `:crypto` module and encoded into a low-density 2D QR code (guaranteed < 450 bytes) rendered as an SVG via `eqrcode`. Printing is dispatched interactively via a client JS hook (`window.print()`) styled with clean `@media print` rules and headlessly via an abstract `RxGenerator.Printing.Spooler` behaviour tested using `Mox`. Cryptographic determinism and 100% tamper detection are proven via `StreamData` property fuzzing.

## Technical Context

**Language/Version**: Elixir ~> 1.17, Erlang/OTP 27+
**Primary Dependencies**: 
- Erlang native `:crypto` (`:ed25519`)
- `AshStateMachine` 0.2
- `AshArchival` 2.0
- `Ash` 3.0 / `AshPhoenix` 2.0
- `Phoenix.LiveView` 1.2
- `eqrcode` (embedded pure Elixir QR generator)
- `Mox` (hardware spooler test double)
- `StreamData` 1.4 (property-based fuzz testing)
**Storage**: SQLite3 (`ash_sqlite` / `ecto_sqlite3`) with unique index on `prescriptions(rx_number)`
**Testing**: ExUnit, `Phoenix.LiveViewTest`, `Mox`, `StreamData`
**Target Platform**: Edge local PC / air-gapped clinic workstation (Windows / Linux)
**Project Type**: Phoenix LiveView Web Application
**Performance Goals**:
- Manifest compilation & Ed25519 signing < 15ms
- QR SVG generation < 25ms
- Offline signature verification < 5ms
- QR payload byte size < 450 bytes for up to 10 line items (~374 bytes)
**Constraints**:
- Strictly air-gapped (zero external cloud network calls or remote key managers)
- Low-spec clinic hardware memory overhead < 250MB RAM
- 100% offline verification against local BM&DC provider registry snapshot
**Scale/Scope**: Outpatient clinical consultation, up to 15 medications per prescription

## Constitution Check

- **Article I (Zero Hallucination)**: PASS. All prescribed drugs remain strictly pinned to verified Directorate General of Drug Administration (DGDA) catalog items.
- **Article II (High Court Generic Mandate)**: PASS. Print layout renders active generic molecules in bold uppercase typography (`String.upcase(generic_name)`) with equal or greater visual prominence than commercial brand names.
- **Article III (HITL Absolute)**: PASS. Physician explicitly triggers the finalization lock; the system never finalizes or modifies prescriptions automatically.
- **Article IV (Controlled Substances)**: PASS. Line item snapshot preserves control flag; narcotic lockouts remain enforced.
- **Article V (Zero-Cloud Edge Autonomy)**: PASS. Signing, manifest compilation, QR rendering, verification, and printing run completely offline without cloud APIs or network calls.
- **Article VI (Memory & Latency SLA)**: PASS. Cryptographic signing (<15ms) and verification (<5ms) execute well within latency bounds on edge PCs.
- **Article VIII (Encryption-at-Rest)**: PASS. Patient identifiers remain protected at rest.
- **Article IX (State Machine Invariance)**: PASS. Core focus of this plan. Transition from `:draft` to `:locked` permanently enforces item immutability across create, update, and destroy actions; soft archival preserved; zero hard deletes.
- **Article X (Ed25519 Offline Authenticity)**: PASS. Core focus of this plan. Detached asymmetric Ed25519 digital signature embedded in 2D QR payload (`MANIFEST#SIG`) and verifiable offline against local BM&DC registry snapshot.
- **Agentic Modification Fence**: PASS. Tech stack strictly scoped to authorized Hex packages (`eqrcode`, `mox`, existing `stream_data`) and Erlang `:crypto`. No cloud network drivers or DB adapter swaps.

## Project Structure

### Documentation (this feature)

```text
specs/003-prescription-finalization-print/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Architectural research & decisions (Hardened)
├── data-model.md        # Ash resources, state machines, and cryptographic structs (Hardened)
├── quickstart.md        # Runnable verification suites & test scenarios
├── contracts/           # Interfaces and protocols
│   ├── manifest_contract.md   # Canonical manifest grammar & QR schema (<450 bytes)
│   └── spooler_contract.md    # Print spooler behaviour & LiveView event protocols
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code Architecture

```text
lib/
├── rx_generator/
│   ├── prescriptions/
│   │   ├── prescription.ex          # Ash resource with :lock transition & validations
│   │   ├── prescription_item.ex     # Ash resource with destroy-safe ParentIsDraft validation
│   │   ├── manifest.ex              # Deterministic compact manifest struct & compiler (<450 bytes)
│   │   ├── crypto.ex                # Ed25519 offline signing, verification, and key bootstrap
│   │   ├── provider_registry.ex     # Local BM&DC provider public key snapshot interface
│   │   ├── qr_code.ex               # SVG QR code generator (via eqrcode)
│   │   └── verification_result.ex   # Verification evaluation struct
│   ├── prescriptions.ex             # Domain interface (finalize_prescription, verify_payload)
│   └── printing/
│       ├── spooler.ex               # Hardware print spooler behaviour
│       └── os_spooler.ex            # Edge OS print driver implementation
├── rx_generator_web/
│   ├── components/
│   │   └── core_components.ex       # Canvas with print layout, QR SVG, and High Court typography
│   └── live/
│       └── prescription_live.ex     # LiveView finalization lock & print event handlers
test/
├── support/
│   ├── mocks.ex                     # Mox mock for RxGenerator.Printing.Spooler
│   └── crypto_fixtures.ex           # Test keypairs and local BM&DC test fixtures
├── rx_generator/
│   ├── prescriptions/
│   │   ├── immutability_test.exs     # Immutability & destroy-safe state machine tests
│   │   ├── crypto_test.exs           # Ed25519 signing & offline verification tests
│   │   └── manifest_fuzz_test.exs    # StreamData property fuzzing tests
│   └── printing/
│       └── spooler_test.exs         # Mox print spooler driver tests
└── rx_generator_web/
    └── live/
        └── prescription_finalization_live_test.exs # LiveView finalize & print user flow
```

## Complexity Tracking

*No constitutional violations. Design strictly respects all invariants.*

## Phase 0 & Phase 1 Outputs Complete

- **Phase 0 (Research)**: Documented in [`research.md`](file:///d:/Rx_generator/specs/003-prescription-finalization-print/research.md)
- **Phase 1 (Design & Contracts)**:
  - Data models documented in [`data-model.md`](file:///d:/Rx_generator/specs/003-prescription-finalization-print/data-model.md)
  - Canonical manifest & QR payload contract in [`contracts/manifest_contract.md`](file:///d:/Rx_generator/specs/003-prescription-finalization-print/contracts/manifest_contract.md)
  - Print spooler behaviour & event protocols in [`contracts/spooler_contract.md`](file:///d:/Rx_generator/specs/003-prescription-finalization-print/contracts/spooler_contract.md)
  - Quickstart test guide in [`quickstart.md`](file:///d:/Rx_generator/specs/003-prescription-finalization-print/quickstart.md)
