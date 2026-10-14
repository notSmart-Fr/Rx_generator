# Feature Specification: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Feature Branch**: `003-prescription-finalization-print`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Build prescription finalization, offline cryptographic verification, and print spooling. Implement the :lock transition on Prescription enforcing complete immutability on line items. Generate a canonical prescription manifest signed with an offline Ed25519 private key, embedded in a tamper-evident QR code rendered on the prescription canvas. Provide a clean print-optimized layout displaying the High Court uppercase generics and canonical Bengali directions, and trigger physical OS print spooling via a dedicated spooler interface."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prescription Finalization and Immutability Lock (Priority: P1)

As a prescribing physician, I need to finalize an active draft prescription so that it transitions into a permanently locked state where no further modifications, additions, or deletions of medications can occur.

**Why this priority**: Prescriptions represent binding medical-legal orders. Once issued to a patient, altering dosages, active ingredients, or instructions invalidates clinical integrity and introduces severe safety and liability risks. Permanent locking guarantees non-repudiation and medical-legal immutability.

**Independent Test**: Can be fully tested by creating a draft prescription with medication line items, triggering the finalization action, and verifying that the prescription transitions to a locked state where all subsequent attempts to edit, delete, or append medication items are strictly rejected.

**Acceptance Scenarios**:

1. **Given** a draft prescription containing at least one valid medication line item, **When** the physician triggers the finalization action, **Then** the prescription transitions to the locked state, records the finalization timestamp, and disables all interactive editing controls.
2. **Given** an existing prescription in the locked state, **When** any actor attempts to modify an existing medication item, add a new medication item, or delete a medication item, **Then** the operation is rejected with an immutability violation error and the prescription content remains unaltered.
3. **Given** an empty draft prescription with no medication line items, **When** the physician attempts to finalize it, **Then** the system rejects the finalization request with a validation message requiring at least one medication before locking.

---

### User Story 2 - Offline Cryptographic Manifest Signing & QR Code Rendering (Priority: P1)

As a clinic administrator or dispensing pharmacist, I need every finalized prescription to carry an offline-generated digital signature embedded in a compact two-dimensional barcode (QR code) so that the document's authenticity and contents can be verified without requiring an active internet connection or degrading on thermal printers.

**Why this priority**: Counterfeit and altered paper prescriptions are a critical safety hazard. Generating an asymmetric digital signature offline using the prescribing physician's registered credentials guarantees that any post-issuance tampering is immediately detectable. Using a compact, deterministic serialization format keeps the QR density low enough (< 450 bytes) for reliable optical scanning on 203 DPI thermal printers and low-end camera scanners even with 10+ line items.

**Independent Test**: Can be tested by finalizing a prescription with multiple line items, extracting the payload from the generated QR code on the prescription canvas, verifying that payload size is under 450 bytes, and verifying that the canonical manifest verifies successfully against the physician's public key.

**Acceptance Scenarios**:

1. **Given** a draft prescription being finalized by an authenticated physician with a configured offline signing key, **When** the prescription enters the locked state, **Then** the system compiles a deterministic, compact canonical manifest with line items sorted strictly by `display_order ASC`, generates an asymmetric Ed25519 digital signature over the UTF-8 byte representation, and renders a low-density 2D QR code onto the prescription canvas.
2. **Given** a prescription with up to 10 medication line items, **When** the QR code is generated, **Then** the total payload size remains strictly below 450 bytes, ensuring optical legibility on 203 DPI thermal paper.
3. **Given** a physician profile lacking a valid cryptographic signing key in production mode, **When** finalization is requested, **Then** the system halts finalization with a clear notification indicating missing credentials and preserves the prescription in draft state.
4. **Given** a local development, test, or fresh edge clinic environment, **When** physician credentials or signing keys are uninitialized, **Then** an automated bootstrapping mechanism generates a valid local Ed25519 keypair and registers the public key into the local provider registry snapshot so that workflows execute without manual key management.

---

### User Story 3 - High Court Compliant Print Layout and Dual-Dispatch Spooling (Priority: P2)

As a prescribing physician, I need a dedicated, clean, print-optimized document view displaying generic drug names in bold uppercase alongside canonical Bengali dosage instructions, with dual-dispatch printing supporting both immediate browser print preview and headless backend spooling.

**Why this priority**: National healthcare regulations mandate that active molecule names be visibly prominent over commercial brand names to protect patient affordability. Clear Bengali instructions ensure patients correctly comprehend dosage schedules. Dual-dispatch printing enables immediate consultation-room printing via the browser dialog while allowing headless edge spooling to be validated in automated test suites without physical hardware.

**Independent Test**: Can be tested by opening a finalized prescription in print preview, asserting that generic molecules appear in uppercase typography with equal or greater visual hierarchy than brand names, asserting that Bengali dosage directions are rendered legibly, verifying that interactive controls are hidden via `@media print`, and validating print payload dispatch via the backend spooler interface.

**Acceptance Scenarios**:

1. **Given** a finalized prescription, **When** the user switches to or triggers the print view, **Then** the document displays the active generic names in bold uppercase typography (`String.upcase(generic_name)`), presents dosage forms, strengths, and canonical Bengali instructions clearly, and suppresses all non-clinical user interface elements (navigation bars, omnibars, search panels).
2. **Given** a finalized prescription view, **When** the physician activates the interactive print action, **Then** the client immediately triggers `window.print()` using print-optimized styles.
3. **Given** an automated test suite or unattended edge hardware setup, **When** the backend print spooler is invoked with a finalized prescription, **Then** the system dispatches the print job through a dedicated spooler interface that can be verified and isolated without requiring a physical printer.
4. **Given** a draft (unlocked) prescription, **When** the user attempts to trigger the print action, **Then** the system warns the user that only finalized prescriptions can be spooled, or presents a distinct "DRAFT / UNVERIFIED" watermark on the preview.

---

### User Story 4 - Offline Verification of Prescription Authenticity (Priority: P2)

As a dispensing pharmacist or medical auditor, I need to scan or input a prescription's cryptographic QR payload to verify whether the paper prescription is authentic, originates from a registered physician, and has not suffered any alterations.

**Why this priority**: Dispensaries and inspection teams need an instant, reliable method to validate prescriptions at point-of-dispense without relying on hospital network access or centralized cloud registries.

**Independent Test**: Can be tested by providing a valid signed prescription payload to the verification utility and checking that it confirms authenticity against the local provider registry, as well as providing a modified payload and confirming that it reports signature failure.

**Acceptance Scenarios**:

1. **Given** a valid QR payload from a printed prescription and a local provider registry snapshot containing the physician's public key, **When** the verifier checks the payload, **Then** the system confirms valid signature status, displays the authenticated physician name and registration number, and displays the exact prescribed line items.
2. **Given** a QR payload where any field (such as a medication dosage or prescription date) has been altered after signing, **When** the verifier checks the payload, **Then** the system identifies the signature mismatch, flags the document as tampered/invalid, and displays an explicit fraud warning.
3. **Given** a QR payload signed with a key not found in the local verified provider registry, **When** the verifier checks the payload, **Then** the system alerts the verifier that the signing authority is unrecognized.

---

### Edge Cases

- **QR Optical Density Degradation (The 10-Item Prescription Hazard)**: If a prescription contains 8 to 12 medication items, verbose JSON must not be used. The compact delimited manifest schema guarantees the payload remains under 450 bytes, preventing QR version bloating and ensuring optical readability on 203 DPI thermal printers.
- **Deterministic Key Preimage Invariance (Signature Mismatch Trap)**: Map iteration order must never be used directly for signature preimages. Manifest fields and line items MUST be compiled in an explicit, deterministic sequence (sorted by `display_order ASC`), ensuring 100% signature verification reproducibility across different OTP builds and architectures.
- **Missing or Corrupt Signing Key**: In production, if the physician's local private key file is unreadable or corrupted, finalization rolls back cleanly with a clear error without mutating the draft state. In development or test mode, the system self-bootstraps missing keys into the local fixture registry.
- **Modification Attempts on Locked Prescriptions**: If an automated script, background job, or UI bypass attempts to add, update, or soft-delete a medication line item on a finalized prescription, the system must abort the transaction and raise an immutability validation error.
- **Zero Medication Finalization**: If a user attempts to finalize a prescription containing zero active line items, finalization is blocked.
- **Paper Sizing and Pagination Overflows**: For prescriptions with numerous line items, the print layout must paginate cleanly without clipping headers, footers, doctor credentials, or the verification QR code.
- **Print Spooler Cancellation**: If the operating system print dialog is cancelled by the user, the prescription state remains locked and ready for subsequent re-spooling without re-signing.
- **Offline Operation During Verification**: Cryptographic verification must execute completely within local memory using local registry snapshots; network disconnection must not degrade verification functionality.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support an explicit finalization action that transitions a prescription from draft to locked state.
- **FR-002**: The system MUST reject any operation that creates, modifies, or deletes medication line items associated with a prescription in the locked state.
- **FR-003**: The system MUST require at least one active medication line item before allowing a prescription to transition to the locked state.
- **FR-004**: Upon finalization, the system MUST compile a byte-deterministic, compact canonical manifest. Line items MUST be sorted strictly by `display_order ASC`. The payload format MUST be structurally minimized (e.g. versioned delimited tokens, targeting under 450 bytes) to prevent optical scanning failure on 203 DPI thermal printers.
- **FR-005**: The system MUST cryptographically sign the canonical manifest using an offline asymmetric private key (Ed25519) producing a byte-reproducible digital signature over the exact UTF-8 canonical preimage.
- **FR-006**: The system MUST encode the compact canonical manifest and its detached digital signature into a standard 2D barcode (QR code) and render it directly on the prescription canvas.
- **FR-007**: The system MUST provide an offline verification mechanism that validates the QR code manifest and detached signature against the physician's public key stored in a local provider registry snapshot.
- **FR-008**: The verification mechanism MUST flag any alteration in prescription text, dosages, dates, or identities as a signature verification failure.
- **FR-009**: The prescription canvas MUST provide a dedicated print layout conforming to national healthcare directives, displaying active generic molecules in bold uppercase typography (`String.upcase(generic_name)`) with visual prominence equal to or greater than commercial brand names.
- **FR-010**: The print layout MUST display canonical Bengali dosage instructions, timing notes, and duration expressions alongside each medication item.
- **FR-011**: The print layout MUST cleanly suppress all interactive web controls, input fields, navigation elements, and search bars when presented in print preview or sent to print (`@media print`).
- **FR-012**: The print subsystem MUST support dual dispatch: (1) client-side interactive browser printing (`window.print()`) styled via `@media print` CSS rules, and (2) an abstract backend print spooler interface enabling unattended physical or headless spooling that can be isolated and verified in automated test suites without requiring physical printer hardware.
- **FR-013**: The system MUST maintain historical audit trails and prevent hard deletion of prescriptions and prescription line items.
- **FR-014**: All cryptographic signing, QR generation, manifest compilation, and print formatting MUST execute entirely edge-native without external network calls or cloud dependencies.
- **FR-015**: The system MUST provide an automated keypair bootstrapping mechanism for development, testing, and edge initialization to generate a valid local Ed25519 keypair and register the corresponding public key in the local provider registry.

### Key Entities *(include if feature involves data)*

- **Prescription**: The primary clinical document representing a medical consultation. Contains attributes such as unique prescription number, issue timestamp, patient identity attributes, physician registration number (BM&DC No.), lifecycle state (`draft`, `locked`), canonical manifest, and cryptographic signature payload.
- **Prescription Line Item**: A specific medication entry linked to a prescription. Contains snapshots of brand name, uppercase generic molecule name, dosage form, strength, dosage matrix (e.g., `1+0+1`), duration, and canonical Bengali instructional text.
- **Prescriber Identity & Keypair**: Represents the licensed practitioner with their registration credentials, public identity, and locally accessible asymmetric signing key (Ed25519) used to generate verifiable digital signatures.
- **Canonical Prescription Manifest**: A deterministic, structured representation of the finalized prescription data used as the preimage for cryptographic signing and verification.
- **Verification Result**: The evaluation outcome produced by the verification mechanism, containing signature validity (`valid`, `invalid`, `unknown_signer`), decoded manifest attributes, verified physician details, and timestamp.
- **Print Spooler Interface**: The abstraction responsible for dispatching print jobs to physical devices or test doubles.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of mutation attempts (insert, update, delete) against line items on finalized prescriptions are rejected by the domain model.
- **SC-002**: Generating a signed compact manifest and rendering the resulting QR code takes under 50 milliseconds on standard edge clinic hardware.
- **SC-003**: 100% of printed or rendered prescriptions display the active generic molecule name in bold uppercase lettering with visual sizing equal to or larger than the commercial brand.
- **SC-004**: Offline verification of a prescription QR code completes in under 20 milliseconds without internet connectivity.
- **SC-005**: 100% of tampered manifests (altering any character of medicine name, dosage, or date) are successfully detected and rejected during verification.
- **SC-006**: The interactive print action triggers the system print preview in under 100 milliseconds upon user click.
- **SC-007**: The entire finalization, signing, and printing workflow functions with zero active network adapters or internet connectivity.
- **SC-008**: The generated QR code payload remains strictly below 450 bytes for prescriptions with up to 10 medication line items, guaranteeing reliable optical scanning on 203 DPI thermal printers.

## Assumptions

- **Local Key Storage**: Prescribing physicians have their asymmetric private keys pre-provisioned or securely stored on their local edge device or session profile, accessible to the application runtime without external key management services.
- **Local Provider Registry Snapshot**: A verified local database snapshot of physician registration numbers (BM&DC) and corresponding public keys is accessible locally on the edge device for verification workflows.
- **Native OS & Browser Printing**: The edge terminal runs a modern desktop operating system and browser capable of interfacing with standard local or network document printers via `@media print` and native print spoolers.
- **Language Localization**: Bengali translation maps and formatting strings are bundled locally with the edge application to ensure translation of directions functions air-gapped.
- **Test Key Bootstrapping**: Automated test suites and local development environments automatically initialize ephemeral or fixture keypairs to prevent setup friction.
