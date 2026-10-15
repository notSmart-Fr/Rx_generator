# Tasks: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Feature**: `003-prescription-finalization-print`
**Spec**: [spec.md](file:///d:/Rx_generator/specs/003-prescription-finalization-print/spec.md) | **Plan**: [plan.md](file:///d:/Rx_generator/specs/003-prescription-finalization-print/plan.md)

---

## Phase 1: Setup & Dependencies

**Purpose**: Configure authorized cryptographic, QR rendering, and test mocking dependencies, setup local offline key directories, and establish Mox doubles.

- [X] T001 Add `{:eqrcode, "~> 0.1.10"}` and `{:mox, "~> 1.2", only: :test}` to `deps` in `mix.exs` and execute `mix deps.get`
- [X] T002 [P] Create local key storage directory `priv/keys/` and add `priv/keys/*.pem` (excluding sample public keys) to `.gitignore`
- [X] T003 [P] Define `RxGenerator.Printing.MockSpooler` using `Mox.defmock/2` in `test/support/mocks.ex` and configure `Mox` in `test/test_helper.exs`
- [X] T004 [P] Create `test/support/crypto_fixtures.ex` containing deterministic Ed25519 keypairs, sample physician BM&DC records, and provider registry fixture data

---

## Phase 2: Foundational Data Layer & Schema Hardening

**Purpose**: Extend `Prescription` with cryptographic and timestamp fields, add partial unique indexes, harden `ParentIsDraft` validation against destroy blind spots, and establish the local provider registry.

- [X] T005 Update `RxGenerator.Prescriptions.Prescription` in `lib/rx_generator/prescriptions/prescription.ex` adding attributes: `canonical_manifest` (:string, allow_nil?: true), `signature` (:string, allow_nil?: true), `finalized_at` (:utc_datetime_usec, allow_nil?: true), and identity `identity :unique_rx_number, [:rx_number]`
- [X] T006 Generate and apply Ash SQLite database migration for new prescription signing fields via `mix ash.codegen add_prescription_signing_fields` and `mix ash.migrate`
- [X] T007 Harden `RxGenerator.Prescriptions.Validations.ParentIsDraft` in `lib/rx_generator/prescriptions/validations/parent_is_draft.ex` to check `changeset.data.prescription_id || Ash.Changeset.get_attribute(changeset, :prescription_id)` against parent prescription state, guaranteeing that `destroy` (soft-archival) actions are blocked on `:locked` prescriptions
- [X] T008 [P] Implement `RxGenerator.Prescriptions.ProviderRegistry` in `lib/rx_generator/prescriptions/provider_registry.ex` providing local offline BM&DC public key lookup (`get_public_key/1` and `register_provider/2`)
- [X] T009 [P] Implement self-bootstrapping Ed25519 keypair generator in `lib/rx_generator/prescriptions/crypto.ex` to automatically provision a local signing key in `:dev` and `:test` environments if `priv/keys/doctor_signing_key.pem` is absent

**Checkpoint**: Foundation ready — database schema updated, destroy validation hardened, and local cryptographic provider registry established.

---

## Phase 3: User Story 1 - Prescription Finalization and Immutability Lock (Priority: P1) 🎯 MVP

**Goal**: A physician finalizes an active draft prescription, triggering the `:lock` transition that permanently prohibits any line item creation, modification, or soft-deletion.

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/immutability_test.exs` asserting that an active prescription transitions to `:locked`, rejecting empty prescriptions and all subsequent item mutations.

### Tests for User Story 1 (Strict Red-First TDD) 🔴

- [X] T010 [P] [US1] Create unit test in `test/rx_generator/prescriptions/immutability_test.exs` asserting that `:lock` action transitions state from `:draft` to `:locked`, rejects prescriptions with 0 items, and verify it fails (Red)
- [X] T011 [P] [US1] Create immutability test in `test/rx_generator/prescriptions/immutability_test.exs` asserting that calling `create_item`, updating an item, or calling `remove_item` on a `:locked` prescription returns an error, and verify it fails (Red)

### Implementation for User Story 1 🟢

- [X] T012 [US1] Configure the `:lock` update action in `lib/rx_generator/prescriptions/prescription.ex` to accept `[:canonical_manifest, :signature, :finalized_at]`, validate `items` is non-empty (`length(items) > 0`), and execute `change transition_state(:locked)`
- [X] T013 [US1] Implement `finalize_prescription/2` in `lib/rx_generator/prescriptions.ex` loading items and executing the `:lock` action with atomic timestamping
- [X] T014 [US1] Implement `handle_event("finalize_prescription", _params, socket)` in `lib/rx_generator_web/live/prescription_live.ex` calling `Prescriptions.finalize_prescription/2` and updating socket state
- [X] T015 [US1] Update `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex` to display a "Finalize Prescription" button when `:draft` and a prominent "FINALIZED & IMMUTABLE" security badge when `:locked`, while disabling omnibar editing controls

**Checkpoint**: User Story 1 (MVP) complete — prescriptions can be locked, and line items are permanently immutable across create, update, and soft-delete actions.

---

## Phase 4: User Story 2 - Offline Cryptographic Manifest Signing & QR Code Rendering (Priority: P1)

**Goal**: Finalization atomically compiles a deterministic canonical manifest (<450 bytes) with items sorted by `display_order ASC`, signs it with the physician's offline Ed25519 private key, and renders a low-density 2D QR code vector SVG onto the prescription canvas.

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/crypto_test.exs` and `mix test test/rx_generator/prescriptions/manifest_fuzz_test.exs` asserting byte-deterministic signing, payload under 450 bytes, and valid QR SVG rendering.

### Tests for User Story 2 (Strict Red-First TDD) 🔴

- [X] T016 [P] [US2] Create unit test in `test/rx_generator/prescriptions/crypto_test.exs` asserting canonical manifest compilation with sanitized delimiters (`|` and `:`), 8-character `short_drug_id`, integer timestamp (`DateTime.to_unix/2`), and sorting by `display_order ASC`, and verify it fails (Red)
- [X] T017 [P] [US2] Create cryptographic test in `test/rx_generator/prescriptions/crypto_test.exs` asserting `:crypto.sign(:eddsa, :none, ...)` produces a 64-byte Ed25519 signature verifiable against the doctor's public key, and verify it fails (Red)
- [X] T018 [P] [US2] Create property-based fuzz test in `test/rx_generator/prescriptions/manifest_fuzz_test.exs` using `StreamData` asserting byte-level serialization determinism and asserting QR payload size is strictly < 450 bytes for prescriptions with up to 10 line items, and verify it fails (Red)

### Implementation for User Story 2 🟢

- [X] T019 [P] [US2] Define `RxGenerator.Prescriptions.Manifest` struct and implement `compile/1` in `lib/rx_generator/prescriptions/manifest.ex` sorting items strictly by `display_order ASC, then id ASC`, sanitizing internal `|` and `:` to `_`, and extracting 8-char `short_drug_id` prefixes
- [X] T020 [P] [US2] Implement `sign_manifest/2` and `verify_manifest/3` in `lib/rx_generator/prescriptions/crypto.ex` using Erlang native `:crypto.sign/4` and `:crypto.verify/5` with algorithm `:ed25519`
- [X] T021 [P] [US2] Implement `RxGenerator.Prescriptions.QRCode` in `lib/rx_generator/prescriptions/qr_code.ex` wrapping `eqrcode` to render raw SVG markup strings from `manifest#signature` payloads
- [X] T022 [US2] Integrate manifest signing and QR generation into `Prescriptions.finalize_prescription/2` in `lib/rx_generator/prescriptions.ex` so manifest and signature are atomically persisted upon locking
- [X] T023 [US2] Update `PrescriptionLive` in `lib/rx_generator_web/live/prescription_live.ex` and `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex` to render the SVG QR code element with physician BM&DC metadata upon finalization

**Checkpoint**: User Stories 1 AND 2 complete — locked prescriptions carry offline-signed, tamper-evident QR codes with payload sizes safely below 450 bytes.

---

## Phase 5: User Story 3 - High Court Compliant Print Layout and Dual-Dispatch Spooling (Priority: P2)

**Goal**: Provide a clean, print-optimized document view displaying High Court uppercase generics and canonical Bengali instructions, with dual-dispatch printing via client JS hook (`window.print()`) and backend `RxGenerator.Printing.Spooler` driver.

**Independent Test**: Can be verified by running `mix test test/rx_generator/printing/spooler_test.exs` and `mix test test/rx_generator_web/live/prescription_finalization_live_test.exs` asserting print button dispatch and print CSS classes.

### Tests for User Story 3 (Strict Red-First TDD) 🔴

- [X] T024 [P] [US3] Create unit test in `test/rx_generator/printing/spooler_test.exs` asserting that invoking `RxGenerator.Printing.Spooler.spool/2` delegates to `RxGenerator.Printing.MockSpooler` using `Mox.expect/4`, and verify it fails (Red)
- [X] T025 [P] [US3] Create LiveView test in `test/rx_generator_web/live/prescription_finalization_live_test.exs` asserting that clicking the print button on a finalized prescription pushes `"print_prescription"` event to client, and verify it fails (Red)

### Implementation for User Story 3 🟢

- [X] T026 [P] [US3] Define `RxGenerator.Printing.Spooler` behaviour in `lib/rx_generator/printing/spooler.ex` with callback `@callback spool(prescription :: Prescription.t(), opts :: keyword()) :: :ok | {:error, term()}`
- [X] T027 [P] [US3] Implement `RxGenerator.Printing.OSSpooler` in `lib/rx_generator/printing/os_spooler.ex` interfacing with system printing capabilities
- [X] T028 [US3] Configure `:print_spooler` in `config/config.exs` (pointing to `OSSpooler`) and `config/test.exs` (pointing to `MockSpooler`)
- [X] T029 [P] [US3] Create client JavaScript print hook in `assets/js/hooks/print_prescription.js` listening for `"print_prescription"` event and calling `window.print()`
- [X] T030 [US3] Register `PrintPrescription` hook in `assets/js/app.js`
- [X] T031 [P] [US3] Add `@media print` CSS rules in `assets/css/app.css` to hide `#prescription-omnibar`, navigation, and HUD controls, expand `#prescription-canvas` to 100% width, format bold uppercase generics (`.generic-name-print`), and prevent page breaks inside medication rows
- [X] T032 [US3] Update `<.prescription_canvas>` in `lib/rx_generator_web/components/core_components.ex` to display an interactive "Print Prescription" button when locked and apply High Court typography classes

**Checkpoint**: User Story 3 complete — print layout adheres to High Court generic mandates, and dual-dispatch spooling operates seamlessly across browser and headless drivers.

---

## Phase 6: User Story 4 - Offline Verification of Prescription Authenticity (Priority: P2)

**Goal**: Dispensaries and audit agents can parse a prescription QR code payload, resolve the physician's public key from the local BM&DC registry snapshot, verify the signature, and detect any post-issuance tampering.

**Independent Test**: Can be verified by running `mix test test/rx_generator/prescriptions/verification_test.exs` asserting 100% detection of tampered manifests, altered dosages, and unknown signers.

### Tests for User Story 4 (Strict Red-First TDD) 🔴

- [X] T033 [P] [US4] Create unit test in `test/rx_generator/prescriptions/verification_test.exs` asserting that `verify_qr_payload/1` returns `{:ok, %VerificationResult{status: :valid}}` for authentic payloads, and verify it fails (Red)
- [X] T034 [P] [US4] Create tamper detection test in `test/rx_generator/prescriptions/verification_test.exs` asserting that mutating any single character in the manifest or signature returns `{:error, %VerificationResult{status: :signature_mismatch}}`, and verify it fails (Red)
- [X] T035 [P] [US4] Create unknown signer test in `test/rx_generator/prescriptions/verification_test.exs` asserting that payloads signed by an unregistered BM&DC number return `{:error, %VerificationResult{status: :unknown_signer}}`, and verify it fails (Red)

### Implementation for User Story 4 🟢

- [X] T036 [P] [US4] Define `RxGenerator.Prescriptions.VerificationResult` struct in `lib/rx_generator/prescriptions/verification_result.ex` with fields: `valid?`, `status`, `rx_number`, `prescriber_bmdc_no`, `prescriber_name`, `timestamp`, `items`, `error_message`
- [X] T037 [US4] Implement `verify_qr_payload/1` in `lib/rx_generator/prescriptions/crypto.ex` splitting `manifest#signature`, resolving public key via `ProviderRegistry`, and verifying signature with `:crypto.verify/5`
- [X] T038 [US4] Expose `verify_prescription_payload/1` in `lib/rx_generator/prescriptions.ex` as the public domain API for verification

**Checkpoint**: User Story 4 complete — offline verification proves document authenticity and flags all tampering attempts without internet access.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Property-based fuzz verification, end-to-end quickstart execution, and constitutional compliance review.

- [X] T039 Execute property fuzz test suite across 500 iterations via `mix test test/rx_generator/prescriptions/manifest_fuzz_test.exs` confirming zero regressions in determinism and tamper detection
- [X] T040 [P] Run end-to-end validation scenarios documented in `specs/003-prescription-finalization-print/quickstart.md`
- [X] T041 Run `mix precommit` (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`) to guarantee clean build and zero warnings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — executes immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories.
- **User Story 1 (Phase 3 - MVP)**: Depends on Phase 2. Can be delivered as standalone MVP.
- **User Story 2 (Phase 4)**: Depends on Phase 3 (`Prescription` locking action and items).
- **User Story 3 (Phase 5)**: Depends on Phase 3 (locked prescription canvas) and Phase 4 (rendered QR code).
- **User Story 4 (Phase 6)**: Depends on Phase 4 (manifest and signing formats).
- **Polish (Phase 7)**: Depends on completion of all user stories.

### Parallel Opportunities

- **Phase 1**: T002, T003, T004 can run in parallel after T001 (`mix deps.get`).
- **Phase 2**: T008, T009 can run in parallel with T005–T007.
- **User Story 1 (Phase 3)**: Tests T010 and T011 can run in parallel.
- **User Story 2 (Phase 4)**: Tests T016, T017, T018 can run in parallel. Implementation tasks T019, T020, T021 can run in parallel across separate files (`manifest.ex`, `crypto.ex`, `qr_code.ex`).
- **User Story 3 (Phase 5)**: Tests T024 and T025 can run in parallel. Implementation tasks T026, T027, T029, T031 can run in parallel across separate files.
- **User Story 4 (Phase 6)**: Tests T033, T034, T035 can run in parallel. Implementation task T036 can run in parallel with tests.

---

## Parallel Example: User Story 2

```bash
# Launch tests for User Story 2 in parallel:
Task: "test/rx_generator/prescriptions/crypto_test.exs"
Task: "test/rx_generator/prescriptions/manifest_fuzz_test.exs"

# Launch implementation modules for User Story 2 in parallel:
Task: "lib/rx_generator/prescriptions/manifest.ex"
Task: "lib/rx_generator/prescriptions/crypto.ex"
Task: "lib/rx_generator/prescriptions/qr_code.ex"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`eqrcode`, `mox`, directories, fixtures).
2. Complete Phase 2: Foundational (migration, `ParentIsDraft` destroy hardening, `ProviderRegistry`).
3. Complete Phase 3: User Story 1 (implements `:lock` transition and item immutability).
4. **STOP and VALIDATE**: Verify that prescriptions lock and reject item modifications. This gives an immediate functional increment.

### Incremental Delivery

1. Setup + Foundational → Foundation primed.
2. User Story 1 → Drafts lock and become permanently immutable (MVP!).
3. User Story 2 → Finalization compiles compact manifest and signs offline Ed25519 QR code.
4. User Story 3 → Print layout renders bold uppercase generics and dispatches to spooler.
5. User Story 4 → Offline verification validates QR code against local provider registry.
6. Polish → Property fuzzing and `mix precommit` clean build.
