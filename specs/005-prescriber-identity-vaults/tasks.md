# Tasks: Prescriber Identity Management, Multi-Chamber Configuration, and Encrypted Patient Vaults

**Input**: Design documents from `specs/005-prescriber-identity-vaults/`  
**Prerequisites**: [plan.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/plan.md), [spec.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/spec.md), [research.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/research.md), [data-model.md](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/data-model.md), [contracts/](file:///d:/Rx_generator/specs/005-prescriber-identity-vaults/contracts/)  

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: Maps to specific user story from `spec.md` (`[US1]`, `[US2]`, `[US3]`, `[US4]`, `[US5]`)
- Every task includes explicit file paths and verifiable criteria

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize encryption vault configuration and OTP supervision tree for edge-native operation.

- [ ] T001 Configure `RxGenerator.Vault` in `config/config.exs` and `config/test.exs` setting up `Cloak.Ciphers.AES.GCM` with 256-bit key resolution and `json_library: Jason`
- [ ] T002 [P] Implement `RxGenerator.Vault` module in `lib/rx_generator/vault.ex` using `use Cloak.Vault, otp_app: :rx_generator` with deterministic edge fallback key resolution
- [ ] T003 Add `RxGenerator.Vault` as a permanent worker in the OTP supervision tree in `lib/rx_generator/application.ex` prior to endpoint and domain processes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema migrations and test support fixtures that block all user stories.

**⚠️ CRITICAL**: Must complete before user stories begin.

- [ ] T004 Create database migration in `priv/repo/migrations/20261101160000_setup_prescriber_vault_chambers.exs` creating `prescriber_profiles` and `chamber_configs` tables and adding encrypted BLOB columns (`encrypted_patient_name`, `encrypted_patient_phone`, `encrypted_patient_age`, `encrypted_clinical_notes`) and snapshot fields to `prescriptions`
- [ ] T005 [P] Create test fixture helpers in `test/support/prescriber_fixtures.ex` generating valid `PrescriberProfile`, `ChamberConfig`, and encrypted prescription test structs

**Checkpoint**: Foundation ready — database schema and cryptographic vault initialized.

---

## Phase 3: User Story 1 - Prescriber Identity & BM&DC Registration Configuration (Priority: P1)

**Goal**: Allow physicians to configure their professional profile with verified BM&DC registration details, qualifications, and specialty titles.

**Independent Test**: Create and update a physician profile, assert `bmdc_no` format validation (`~r/^[A-Z]-\d{4,6}$/i`), assert retrieval of the active profile, and verify credentials link to prescription initialization.

### Tests for User Story 1 (Test-First Protocol)
- [ ] T006 [P] [US1] Write unit and domain tests in `test/rx_generator/prescriptions/prescriber_profile_test.exs` asserting valid/invalid BM&DC registration numbers, profile persistence, and active profile retrieval (verify Red before implementation)

### Implementation for User Story 1
- [ ] T007 [P] [US1] Implement `RxGenerator.Prescriptions.PrescriberProfile` Ash resource in `lib/rx_generator/prescriptions/prescriber_profile.ex` with attributes `name` (string, required), `bmdc_no` (string, required, unique), `qualifications` (string, required), `specialty` (string), and `active` (boolean, default true)
- [ ] T008 [US1] Register `PrescriberProfile` in the domain and expose `create_prescriber_profile/1`, `get_active_prescriber/0`, and `update_prescriber_profile/2` in `lib/rx_generator/prescriptions.ex`

**Checkpoint**: Prescriber profiles can be created, validated, and queried independently.

---

## Phase 4: User Story 2 - Multi-Chamber Practice Configuration & Dynamic Header Switching (Priority: P1)

**Goal**: Allow physicians to define multiple practice chambers and toggle between them on the active prescription canvas, instantly updating clinic headers.

**Independent Test**: Configure two distinct practice chambers, attach them to a draft prescription, switch between them via LiveView event, assert immediate canvas header updates (< 15ms), and assert chamber switching is rejected when locked.

### Tests for User Story 2 (Test-First Protocol)
- [ ] T009 [P] [US2] Write chamber resource tests in `test/rx_generator/prescriptions/chamber_config_test.exs` asserting chamber creation, default chamber flags, and prescriber associations (verify Red before implementation)
- [ ] T010 [P] [US2] Write LiveView interaction tests in `test/rx_generator_web/live/prescription_live/chamber_switcher_test.exs` asserting `switch_chamber` event updates canvas headers and is disabled on locked prescriptions (verify Red before implementation)

### Implementation for User Story 2
- [ ] T011 [P] [US2] Implement `RxGenerator.Prescriptions.ChamberConfig` Ash resource in `lib/rx_generator/prescriptions/chamber_config.ex` with attributes `prescriber_profile_id` (uuid, required), `chamber_name` (string, required), `hospital_name` (string), `address` (string, required), `visiting_hours` (string, required), `contact_phone` (string), `is_default` (boolean, default false), and `active` (boolean, default true)
- [ ] T012 [US2] Expose chamber management actions `list_chambers_for_prescriber/1`, `create_chamber/1`, `set_default_chamber/1`, and `set_prescription_chamber/2` in `lib/rx_generator/prescriptions.ex`
- [ ] T013 [US2] Add chamber switcher dropdown/pills and active chamber state handling in `lib/rx_generator_web/live/prescription_live.ex` handling `switch_chamber` events
- [ ] T014 [US2] Update canvas header components in `lib/rx_generator_web/components/core_components.ex` to render doctor credentials and active chamber banner per `contracts/chamber_switcher_contract.md`

**Checkpoint**: Multi-chamber configuration and real-time LiveView switching are functional and independently testable.

---

## Phase 5: User Story 3 - Encrypted Patient Data Vaults for Protected Health Information (Priority: P1)

**Goal**: Encrypt all sensitive patient identifying information (`patient_name`, `patient_phone`, `patient_age`, `clinical_notes`) at rest in SQLite using `ash_cloak` AES-256-GCM, with zero plaintext storage leakage.

**Independent Test**: Create prescriptions with patient demographic data, assert raw SQLite queries return binary ciphertexts starting with `"AES.GCM.V1"`, verify zero plaintext occurrences in the database file, and assert transparent in-memory decryption when loaded through Ash.

### Tests for User Story 3 (Test-First Protocol)
- [ ] T015 [P] [US3] Write vault encryption tests in `test/rx_generator/prescriptions/patient_vault_encryption_test.exs` asserting raw SQLite BLOB ciphertext via direct `Repo.query!/2`, zero plaintext leakage, and transparent Ash calculation decryption (verify Red before implementation)

### Implementation for User Story 3
- [ ] T016 [US3] Configure `AshCloak` extension and `cloak` block on `RxGenerator.Prescriptions.Prescription` in `lib/rx_generator/prescriptions/prescription.ex` encrypting `:patient_name`, `:patient_phone`, `:patient_age`, and `:clinical_notes` via `RxGenerator.Vault` with `encrypt_nil?: false`
- [ ] T017 [US3] Add patient vault update actions `update_patient_details/2` in `lib/rx_generator/prescriptions/prescription.ex` and expose them in `lib/rx_generator/prescriptions.ex`
- [ ] T018 [US3] Update LiveView patient inputs in `lib/rx_generator_web/live/prescription_live.ex` and `lib/rx_generator_web/components/core_components.ex` to display and edit decrypted patient vault attributes

**Checkpoint**: Patient Protected Health Information is encrypted at rest with verified raw ciphertext invariants.

---

## Phase 6: User Story 4 - Cryptographic Binding of Prescriber, Chamber, and Patient to Signed Prescriptions (Priority: P2)

**Goal**: Bind active prescriber credentials and chamber identity into the deterministic Ed25519 digital signature (Manifest V2) and 2D QR code payload (< 450 bytes for 203 DPI thermal printing).

**Independent Test**: Finalize a prescription with an active chamber and prescriber, extract the QR payload, assert total size < 450 bytes for 10 line items, verify against the doctor's public key in the local provider registry, and verify that tampering with chamber or doctor ID invalidates the signature.

### Tests for User Story 4 (Test-First Protocol)
- [ ] T019 [P] [US4] Write Manifest V2 serialization, QR budgeting, and Ed25519 verification tests in `test/rx_generator/prescriptions/manifest_v2_signing_test.exs` (verify Red before implementation)

### Implementation for User Story 4
- [ ] T020 [P] [US4] Implement Manifest V2 canonical schema (`v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>|<items...>`) in `lib/rx_generator/prescriptions/manifest.ex` with delimiter sanitization and deterministic item sorting
- [ ] T021 [US4] Update `lib/rx_generator/prescriptions/crypto.ex` to parse Manifest V2 payloads, resolve prescriber public keys, and verify signatures with chamber metadata
- [ ] T022 [US4] Enhance `:lock` transition in `lib/rx_generator/prescriptions/prescription.ex` to freeze snapshots of active prescriber credentials and chamber header, compile Manifest V2, generate detached Ed25519 signature, and lock the prescription

**Checkpoint**: Prescriptions cryptographically bind prescriber and chamber identities into tamper-evident QR codes.

---

## Phase 7: User Story 5 - High Court Compliant Print Layout Integration with Dynamic Header (Priority: P2)

**Goal**: Render a clean, printable medical prescription layout displaying active chamber banner and physician qualifications alongside bold uppercase generics and Bengali directions, hiding UI controls in `@media print`.

**Independent Test**: Render print view for a locked prescription, verify two-column header with doctor credentials and chamber details, assert bold uppercase generic molecule typography, and assert `@media print` suppresses omnibars and switcher buttons.

### Tests for User Story 5 (Test-First Protocol)
- [ ] T023 [P] [US5] Write print layout integration tests in `test/rx_generator_web/live/prescription_live/print_layout_test.exs` asserting presence of chamber banner, doctor qualifications, uppercase generic molecules, and print CSS utility classes (verify Red before implementation)

### Implementation for User Story 5
- [ ] T024 [US5] Update `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex` to render the High Court compliant two-column printable header (physician on left, chamber on right) and attach `@media print` visibility rules
- [ ] T025 [US5] Wire print triggering and dynamic chamber snapshot assigns in `lib/rx_generator_web/live/prescription_live.ex`

**Checkpoint**: Printable layout cleanly outputs doctor credentials and active chamber headers compliant with High Court directives.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Compliance audits, air-gapped performance verification, and code quality gates.

- [ ] T026 [P] Add air-gap and performance SLA audit test in `test/rx_generator/prescriptions/prescriber_airgap_audit_test.exs` verifying zero external network calls and sub-15ms LiveView chamber switching latency
- [ ] T027 Run quickstart validation scenarios from `specs/005-prescriber-identity-vaults/quickstart.md` across all test suites
- [ ] T028 Run `mix precommit` ensuring zero compiler warnings, code formatting, and 100% passing test suites

---

## Dependencies & Execution Order

```
Phase 1: Setup (T001 - T003)
   │
   ▼
Phase 2: Foundational (T004 - T005)
   │
   ├──────────────────────────┬──────────────────────────┐
   ▼                          ▼                          ▼
Phase 3: US1 (T006-T008)   Phase 4: US2 (T009-T014)   Phase 5: US3 (T015-T018)
   │                          │                          │
   └──────────────────────────┴──────────┬───────────────┘
                                         ▼
                              Phase 6: US4 (T019-T022)
                                         │
                                         ▼
                              Phase 7: US5 (T023-T025)
                                         │
                                         ▼
                              Phase 8: Polish (T026-T028)
```

### User Story Dependencies
- **User Story 1 (P1)**: Starts immediately after Phase 2 (Foundational).
- **User Story 2 (P2)**: Starts after Phase 2; associates `ChamberConfig` with `PrescriberProfile` (US1).
- **User Story 3 (P1)**: Starts immediately after Phase 2; configures `AshCloak` on `Prescription` independently.
- **User Story 4 (P2)**: Requires US1 (prescriber BM&DC), US2 (chamber token), and US3 (`Prescription` updates) to bind into Manifest V2 signing.
- **User Story 5 (P2)**: Requires US2 (chamber header) and US4 (signed QR code) for the complete print layout.

---

## Parallel Execution Opportunities

- **Setup & Foundational**:
  - `T002` (Vault module) can run in parallel with `T001` (config).
  - `T005` (fixtures) can run in parallel with `T004` (migration).
- **User Story Parallelization**:
  - `US1` (Prescriber profile), `US2` (Chambers), and `US3` (Vault encryption) models and unit tests can be developed concurrently once Phase 2 is complete.
  - All test tasks (`T006`, `T009`, `T010`, `T015`, `T019`, `T023`, `T026`) marked `[P]` can be authored in parallel with their corresponding implementation files.

---

## Implementation Strategy (MVP First)

1. **MVP (Phase 1, 2, and 3)**:
   - Configure `RxGenerator.Vault` and database schema.
   - Implement `PrescriberProfile` with BM&DC registration validation.
   - Run `mix test test/rx_generator/prescriptions/prescriber_profile_test.exs` to validate the prescriber identity MVP.
2. **Incremental Delivery**:
   - Deliver `US2` (Chamber configs & LiveView switcher).
   - Deliver `US3` (AshCloak patient data vault at rest).
   - Deliver `US4` (Manifest V2 Ed25519 cryptographic binding).
   - Deliver `US5` (Print layout with dynamic header).
   - Deliver `Polish` (`mix precommit` and air-gap regression tests).

