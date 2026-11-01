# Implementation Plan: Prescriber Identity Management, Multi-Chamber Configuration, and Encrypted Patient Vaults

**Branch**: `005-prescriber-identity-vaults` | **Date**: 2026-11-01 | **Spec**: [spec.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/spec.md)

**Input**: Feature specification from `specs/005-prescriber-identity-vaults/spec.md`

---

## Summary

Implement edge-native prescriber identity management, multi-chamber practice configuration, and encrypted patient data vaults at rest. Physicians configure their legal BM&DC registration details, qualifications, and multiple practice chambers, with real-time chamber switching on the active prescription canvas. All Protected Health Information (PHI)—specifically `:patient_name`, `:patient_phone`, `:patient_age`, and `:clinical_notes`—is encrypted at rest in local SQLite storage via `ash_cloak` and `Cloak` using authenticated AES-256-GCM under the `RxGenerator.Vault` OTP supervisor. When finalized, active prescriber credentials and chamber identity are bound to the deterministic Ed25519 digital signature pipeline (Manifest V2) and 2D QR code payload (< 450 bytes for 203 DPI thermal printing), as well as the High Court-compliant `@media print` layout.

---

## Technical Context

**Language/Version**: Elixir ~> 1.17, Erlang/OTP 27+  
**Primary Dependencies**: 
- `ash_cloak` ~> 0.4 (declarative resource attribute encryption)
- `cloak` ~> 1.0 (`Cloak.Vault` with `Cloak.Ciphers.AES.GCM`)
- `ash` ~> 3.0, `ash_sqlite` ~> 0.2, `ash_state_machine` ~> 0.2
- `phoenix_live_view` ~> 1.2
- `eqrcode` ~> 0.1.10 (compact SVG QR generation)
- Erlang native `:crypto` (`:ed25519`, `:aes_gcm`)  
**Storage**: SQLite3 (`ash_sqlite` / `ecto_sqlite3`) with BLOB columns for ciphertext  
**Testing**: ExUnit, `Phoenix.LiveViewTest`, `StreamData`  
**Target Platform**: Air-gapped edge clinic workstation / PC (Windows / Linux)  
**Project Type**: Phoenix LiveView Web Application (Edge-Native eRx)  
**Performance Goals**:
- Vault encryption/decryption overhead < 2ms per record
- Chamber switching round-trip latency < 15ms DOM patch SLA
- Manifest V2 compilation & Ed25519 signing < 15ms
- QR code payload byte size < 450 bytes for 10 line items (~382 bytes)  
**Constraints**:
- Zero cloud calls, 100% offline air-gapped operation
- Zero plaintext Protected Health Information (PHI) in SQLite disk files
- Hardware RAM footprint < 250MB RAM  
**Scale/Scope**: Outpatient clinical consultations, up to 15 medications, multiple practice locations  

---

## Constitution Check

- **Article I (Zero Hallucination Boundary)**: PASS. All prescribed medications remain strictly pinned to primary keys in the local verified DGDA drug catalog.
- **Article II (High Court Generic Mandate)**: PASS. Active generic molecule names are rendered in bold, uppercase typography (`String.upcase(generic_name)`) with equal or greater visual prominence than commercial brand names in both the canvas and printable layout.
- **Article III (Human-in-the-Loop Absolute)**: PASS. Prescriber identity and chamber selection are explicitly managed by the physician; no algorithmic logic mutates or overrides chamber assignments.
- **Article IV (Controlled Substances Lockout)**: PASS. Narcotic validation rules remain strictly enforced on prescription item actions.
- **Article V (Zero-Cloud Edge Autonomy)**: PASS. Prescriber configuration, multi-chamber switching, vault encryption via `RxGenerator.Vault`, and Ed25519 cryptographic signing run 100% offline without remote cloud APIs or key management servers.
- **Article VI (Memory & Latency SLA)**: PASS. AES-256-GCM encryption overhead (< 2ms) and LiveView chamber switching (< 15ms) operate comfortably within the 15ms latency ceiling and 250MB RAM limit.
- **Article VIII (Encryption-at-Rest for PHI)**: PASS. Core objective of this plan. All patient identifying attributes (`name`, `phone`, `age`, `clinical_notes`) are encrypted at rest in SQLite via `ash_cloak` AES-256-GCM before writing to disk, verified by raw SQL assertions.
- **Article IX (State Machine Invariance)**: PASS. Prescriptions in `:draft` allow chamber switching and patient data edits. Once transitioned to `:locked`, chamber snapshots and prescriber credentials become permanently immutable. Soft archival preserved; zero hard deletes.
- **Article X (Offline Authenticity & Asymmetric Signing)**: PASS. Manifest V2 incorporates prescriber BM&DC registration and chamber token into the preimage signed by the physician's offline Ed25519 private key, verifiable offline against the local provider registry snapshot.
- **Agentic Modification Fence**: PASS. All required libraries (`ash_cloak`, `cloak`, `ash_sqlite`, `eqrcode`) are already included in `mix.exs`. No unauthorized Hex additions, database adapter swaps, or cloud drivers.

---

## Project Structure

### Documentation (this feature)

```text
specs/005-prescriber-identity-vaults/
├── spec.md              # Feature specification
├── plan.md              # This implementation plan
├── research.md          # Architectural research & decisions
├── data-model.md        # Ash resources, Cloak Vault, and schema definitions
├── quickstart.md        # Runnable verification suites & test scenarios
├── contracts/           # Interface contracts and schemas
│   ├── chamber_switcher_contract.md      # LiveView chamber switching & canvas header
│   ├── vault_encryption_contract.md     # Patient vault AES-256-GCM storage invariants
│   └── manifest_v2_signing_contract.md  # Manifest V2 schema & Ed25519 binding
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code Architecture

```text
lib/
├── rx_generator/
│   ├── vault.ex                                 # Cloak.Vault implementation (OTP supervised)
│   ├── application.ex                           # OTP supervision tree including RxGenerator.Vault
│   ├── prescriptions/
│   │   ├── prescriber_profile.ex                # Ash resource for doctor legal identity
│   │   ├── chamber_config.ex                    # Ash resource for practice chamber details
│   │   ├── prescription.ex                      # Enhanced with AshCloak, snapshots, and chamber FK
│   │   ├── manifest.ex                          # Updated for Manifest V2 (prescriber & chamber binding)
│   │   ├── crypto.ex                            # Manifest V2 Ed25519 signing & offline verification
│   │   └── provider_registry.ex                 # Local ETS provider registry with prescriber profiles
│   └── prescriptions.ex                         # Domain interface for prescriber, chamber & vault actions
├── rx_generator_web/
│   ├── components/
│   │   └── core_components.ex                   # Updated canvas header with prescriber & chamber banner
│   └── live/
│       └── prescription_live.ex                 # Dynamic chamber switcher event handling & state
priv/
└── repo/
    └── migrations/
        └── [timestamp]_setup_prescriber_vault_chambers.exs  # SQLite schema migrations
test/
└── rx_generator/
    ├── prescriptions/
    │   ├── prescriber_chamber_test.exs          # Prescriber & chamber configuration tests
    │   ├── patient_vault_encryption_test.exs    # Raw SQLite ciphertext & AshCloak tests
    │   └── manifest_v2_signing_test.exs         # Manifest V2 binding & Ed25519 verification tests
    └── live/
        └── chamber_switcher_test.exs            # LiveView interactive chamber switcher & print tests
```

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | *Fully compliant with constitution* | *N/A* |

---

## Phase 0: Research Review

All research questions and technical unknowns have been resolved in [research.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/research.md):
- **Decision 1**: `RxGenerator.Vault` configured with `Cloak.Ciphers.AES.GCM` and started under `RxGenerator.Application` OTP supervision tree.
- **Decision 2**: `AshCloak` DSL on `Prescription` encrypts `:patient_name`, `:patient_phone`, `:patient_age`, and `:clinical_notes`, backed by `:binary` SQLite columns and verified via raw SQL queries.
- **Decision 3**: Domain separation between `PrescriberProfile` and `ChamberConfig`, with immutable snapshot fields frozen on `Prescription` at `:lock` transition.
- **Decision 4**: Interactive LiveView chamber switcher with sub-15ms DOM patching and disabled state on locked prescriptions.
- **Decision 5**: Manifest V2 schema binds prescriber BM&DC registration and chamber token into Ed25519 signature preimage while keeping payload < 450 bytes.
- **Decision 6**: Print layout renders two-column prescriber/chamber header with bold uppercase generics and suppresses UI controls via `@media print`.

---

## Phase 1: Design & Contracts Review

All Phase 1 artifacts are complete:
1. **Data Model**: Detailed in [data-model.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/data-model.md).
2. **Contracts**:
   - [chamber_switcher_contract.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/contracts/chamber_switcher_contract.md)
   - [vault_encryption_contract.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/contracts/vault_encryption_contract.md)
   - [manifest_v2_signing_contract.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/contracts/manifest_v2_signing_contract.md)
3. **Quickstart & Test Guide**: Detailed in [quickstart.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/quickstart.md).
