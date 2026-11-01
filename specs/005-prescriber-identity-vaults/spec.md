# Feature Specification: Prescriber Identity Management, Multi-Chamber Configuration, and Encrypted Patient Data Vaults

**Feature Branch**: `005-prescriber-identity-vaults`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Build prescriber identity management, multi-chamber configuration, and encrypted patient data vaults. Allow physicians to configure their BM&DC registration details, qualifications, and multiple practice chambers, seamlessly switching active chamber headers on the prescription canvas. Encrypt all patient identifying information (name, phone, age, clinical notes) at rest in SQLite using ash_cloak AES-256-GCM. Bind the active doctor credentials and chamber header to the Ed25519 cryptographic signing pipeline and print layout."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prescriber Identity & BM&DC Registration Configuration (Priority: P1)

As a licensed physician, I need to configure my professional prescriber profile—including my official Bangladesh Medical & Dental Council (BM&DC) registration number, medical degrees, clinical qualifications, and specialty titles—so that every prescription I generate carries legally binding, verifiable medical credentials compliant with national standards.

**Why this priority**: Medical-legal regulations under the BM&DC require every clinical prescription to explicitly state the registered practitioner's credentials, registration number, and clinical qualifications. Without authentic prescriber identity, prescriptions lack legal validity, cannot be verified by dispensaries, and cannot be finalized.

**Independent Test**: Can be tested by creating or updating a physician profile with BM&DC registration details and qualifications, confirming successful persistence and profile retrieval, and verifying that the credentials automatically populate new draft prescriptions.

**Acceptance Scenarios**:

1. **Given** an unconfigured edge installation or initial setup, **When** the physician inputs their full name, BM&DC registration number, primary medical qualifications (e.g., MBBS, FCPS), and clinical specialty designations, **Then** the system validates the registration format, persists the profile, and marks the prescriber identity as active.
2. **Given** a configured prescriber profile, **When** a new prescription draft is initialized, **Then** the active prescriber's name, qualifications, and BM&DC registration number are automatically associated with the draft and displayed on the prescription header.
3. **Given** an attempt to save a prescriber profile with an empty or malformed BM&DC registration number, **When** the form is submitted, **Then** the system rejects the submission with a descriptive validation error and prevents profile activation.

---

### User Story 2 - Multi-Chamber Practice Configuration & Dynamic Header Switching (Priority: P1)

As a practicing physician consulting across multiple hospitals, polyclinics, and private chambers, I need to define multiple practice chamber profiles and seamlessly toggle between them on the active prescription canvas so that the correct clinic header, location address, consultation hours, and emergency contact numbers appear on the patient's prescription.

**Why this priority**: Doctors in Bangladesh frequently practice at two or more consultation chambers with distinct schedules, fees, and location headers. Requiring manual re-entry or separate software installations causes severe administrative friction. Seamless chamber switching ensures the printed prescription accurately guides patients on follow-ups and clinic contact info.

**Independent Test**: Can be tested by setting up two distinct chambers (e.g., "City Hospital OPD" and "Green Life Consultation Centre"), switching between them on an active draft prescription, and asserting that the canvas header and print preview immediately reflect the selected chamber's details.

**Acceptance Scenarios**:

1. **Given** a physician profile, **When** the physician adds multiple practice chambers with distinct clinic names, addresses, visiting hours, and contact numbers, **Then** all chambers are stored under the physician profile with one designated as the default active chamber.
2. **Given** an active draft prescription, **When** the physician selects a different chamber from the chamber switcher, **Then** the prescription canvas header instantly updates its displayed clinic name, address, visiting schedule, and contact telephone without altering any already entered medications.
3. **Given** a prescription that has been finalized and locked, **When** a user attempts to switch the chamber header, **Then** the chamber selection is disabled and locked to preserve historical clinical and legal accuracy.

---

### User Story 3 - Encrypted Patient Data Vaults for Protected Health Information (Priority: P1)

As a healthcare provider and clinical custodian, I need all patient identifying information—including full name, phone number, age, gender, and clinical history notes—to be stored within an encrypted data vault at rest so that patient medical confidentiality is guaranteed even if the local clinic computer or storage drive is lost, stolen, or inspected by unauthorized third parties.

**Why this priority**: Medical ethics and data protection principles mandate strict confidentiality for Protected Health Information (PHI). Storing patient records in unencrypted plain text on edge clinic laptops creates severe privacy liabilities. Encrypting sensitive demographic and clinical data at rest with authenticated ciphers ensures zero plaintext exposure on physical media.

**Independent Test**: Can be tested by creating a patient record with clinical notes, verifying that the application displays decrypted data to authorized clinical views, inspecting the raw underlying storage data to confirm only authenticated ciphertext is stored at rest, and verifying that records can be queried and retrieved reliably.

**Acceptance Scenarios**:

1. **Given** a new or returning patient consultation, **When** the physician or clinical assistant enters patient identifying information (name, phone number, age/DOB, gender) and clinical notes, **Then** the system transparently encrypts all sensitive fields at rest before writing to the database file.
2. **Given** patient records stored on disk, **When** the database file is inspected via external inspection tools without the application encryption keys, **Then** all patient names, phone numbers, ages, and clinical notes appear strictly as random ciphertext with no identifiable plaintext substrings.
3. **Given** an existing patient record in the vault, **When** the physician attaches the patient to an active prescription draft, **Then** the patient demographic details are decrypted in memory and presented clearly on the consultation canvas.

---

### User Story 4 - Cryptographic Binding of Prescriber, Chamber, and Patient to Signed Prescriptions (Priority: P2)

As a medical auditor, dispensing pharmacist, or regulatory inspector, I need every finalized prescription to cryptographically bind the active prescriber's credentials, BM&DC registration number, and selected chamber header into the offline digital signature and 2D barcode (QR code) so that neither prescriber identity nor clinic location can be forged, detached, or tampered with after issuance.

**Why this priority**: Forgery and unauthorized reuse of prescription headers across unauthorized clinic locations is a documented risk. Binding the doctor's verified BM&DC registration and chamber identity into the deterministic manifest signed by the physician's private key ensures end-to-end provenance and non-repudiation.

**Independent Test**: Can be tested by finalizing a prescription under a specific chamber, extracting the cryptographic manifest and signature from the generated QR payload, verifying that the signature validates against the prescriber's registered public key, and confirming that modifying the chamber identifier or BM&DC number invalidates the signature.

**Acceptance Scenarios**:

1. **Given** an active draft prescription with an assigned chamber and prescriber, **When** the physician triggers prescription finalization, **Then** the canonical manifest compilation incorporates the prescriber's BM&DC number and the active chamber identifier into the deterministic preimage before generating the asymmetric digital signature.
2. **Given** a generated QR payload containing the signed manifest, **When** the offline verification engine inspects the payload, **Then** the verified output displays the authenticated prescriber name, BM&DC registration number, and chamber details alongside the prescribed medications.
3. **Given** a signed prescription payload where the chamber header or prescriber registration has been altered, **When** the payload is verified, **Then** the cryptographic verification fails with an explicit signature mismatch error.

---

### User Story 5 - High Court Compliant Print Layout Integration with Dynamic Header (Priority: P2)

As a prescribing physician, I need the printable document view and physical print spooler to render the selected chamber header, physician qualifications, and BM&DC registration clearly at the top of the prescription, while keeping generic molecule names prominently displayed in uppercase in accordance with High Court directives.

**Why this priority**: The printed prescription is the final legal artifact handed to the patient. It must present complete clinic contact information and doctor credentials at the header, followed by bold uppercase generic medications and clear dosage instructions, accompanied by the offline verification seal.

**Independent Test**: Can be tested by triggering print preview on a locked prescription, verifying that the selected chamber banner and doctor qualifications render crisply without clipping, verifying uppercase generic medication hierarchy, and validating that the print stylesheet cleanly suppresses navigation controls.

**Acceptance Scenarios**:

1. **Given** a finalized prescription with an active chamber, **When** the user accesses print preview or triggers printing, **Then** the document displays a structured header containing the doctor's name, qualifications, BM&DC registration number, chamber name, address, contact numbers, and consultation hours.
2. **Given** a prescription printed across different chambers on consecutive consultations, **When** printed, **Then** each printout reflects only the chamber header selected for that specific prescription.
3. **Given** a print layout rendering, **When** viewed in print media mode (`@media print`), **Then** interactive editing controls, omnibars, and chamber switching menus are hidden from the printed output.

---

### Edge Cases

- **Chamber Switching on Locked Prescriptions**: If a user attempts to switch chambers after finalization, the system strictly forbids mutation and preserves the locked chamber association.
- **Deactivating or Deleting an In-Use Chamber**: If an active chamber is archived or deactivated, historical locked prescriptions continue to display their original chamber snapshot, and the system prompts the physician to select an alternative active chamber for future drafts.
- **Physician Qualification Typography Overflow**: If a physician enters extensive postgraduate degrees and fellowship titles, the header layout wraps gracefully across multiple lines without truncating or displacing the prescription medication area.
- **Offline Key Availability for Vault Decryption**: If the clinic computer reboots without network access, the local encryption keys remain available via environment or local secret configuration so that patient records can be read and written 100% offline.
- **Patient Search Across Encrypted Records**: When searching for patients in the vault (e.g. by telephone number or patient identifier), lookup executes securely using deterministic search tokens or indexed vault identifiers without exposing raw plaintext in database index files.
- **Zero-Chamber Fallback**: If a prescriber profile is created without any chambers configured, the system provides a default "Main Practice Chamber" placeholder or requires at least one chamber before allowing prescriptions to be finalized.
- **Prescriber Profile Updates**: If the physician updates their degree or qualifications (e.g., passing a new specialty exam), subsequent draft prescriptions adopt the updated credentials, while historical locked prescriptions retain their immutable snapshot.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST allow a physician to configure and manage their prescriber profile, including full name, BM&DC registration number, degrees/qualifications, and clinical specialty titles.
- **FR-002**: The system MUST enforce non-empty validation on the BM&DC registration number before a physician profile can be activated for prescribing.
- **FR-003**: The system MUST allow a physician to configure multiple practice chambers, each with a clinic/hospital name, location address, consultation hours/schedule, and contact telephone numbers.
- **FR-004**: The system MUST support designating one chamber as the default active chamber, which automatically attaches to newly created prescription drafts.
- **FR-005**: The system MUST provide an interactive chamber switcher on the draft prescription canvas allowing the physician to toggle the active chamber header with immediate visual feedback.
- **FR-006**: The system MUST permanently lock the chamber association and prescriber credentials when a prescription transitions to the locked state, rejecting any subsequent modifications.
- **FR-007**: The system MUST provide an encrypted patient data vault that encrypts Protected Health Information (patient name, phone number, age/DOB, gender, and clinical notes) at rest using authenticated symmetric encryption (AES-256-GCM).
- **FR-008**: The system MUST ensure that patient identifying fields in the database storage file contain only binary or encoded ciphertext with no plaintext fragments visible during raw data inspection.
- **FR-009**: The system MUST transparently decrypt patient records in memory for authorized clinical viewing and consultation rendering without requiring external cloud key management services.
- **FR-010**: The system MUST allow attaching an existing or newly created patient record from the encrypted vault to an active prescription draft.
- **FR-011**: The system MUST incorporate the active prescriber's BM&DC registration number and the active chamber identifier into the canonical manifest preimage before generating the offline asymmetric digital signature (Ed25519).
- **FR-012**: The system MUST generate a tamper-evident 2D barcode (QR code) embedding the signed manifest containing prescriber and chamber identity, remaining under the optical scanning density threshold (< 450 bytes) for standard 203 DPI thermal printers.
- **FR-013**: The system MUST provide an offline verification capability that validates the cryptographic signature of the QR payload against the prescriber's public key stored in the local provider registry snapshot.
- **FR-014**: The system MUST render the active prescriber's credentials and selected chamber header on the print layout, formatted cleanly alongside bold uppercase generic drug names and Bengali dosage instructions.
- **FR-015**: The system MUST execute all prescriber management, chamber switching, vault encryption/decryption, and signing workflows entirely offline without relying on external cloud APIs or internet connectivity.

### Key Entities

- **Prescriber Profile**: Represents the licensed physician; attributes include unique physician identifier, full name, BM&DC registration number, clinical qualifications (degrees/fellowships), specialty designations, and cryptographic signing key reference.
- **Practice Chamber**: Represents a clinical practice location; attributes include unique chamber identifier, prescriber reference, chamber name, address/location text, consultation hours/schedule, contact phone numbers, and a default chamber flag.
- **Patient Vault Record**: Represents patient demographic and medical-legal data; attributes include unique patient identifier, encrypted name, encrypted contact phone, encrypted age/date of birth, encrypted gender, encrypted clinical notes/history, and audit timestamps.
- **Prescription (Enhanced Association)**: Represents the clinical order; links the prescription record to the active Prescriber Profile, the selected Practice Chamber, and the Patient Vault Record, freezing immutable snapshots upon transition to the locked state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Physicians can switch the active chamber header on the prescription canvas in under 1 second (interactive round-trip under 100ms), immediately updating the on-screen header.
- **SC-002**: 100% of patient identifying fields (name, phone, age, clinical notes) in the database file are confirmed to be encrypted ciphertext at rest, with zero plaintext leakage in database dumps or storage scans.
- **SC-003**: 100% of finalized prescriptions successfully incorporate the prescriber BM&DC registration and chamber identity into the cryptographic manifest, verifying cleanly against the prescriber's offline public key.
- **SC-004**: Total QR code payload size for prescriptions containing up to 10 medication line items with prescriber and chamber tokens remains under 450 bytes, ensuring 100% optical scanning success on 203 DPI thermal paper.
- **SC-005**: All prescriber profile setups, chamber configuration changes, patient vault creations, and prescription signing workflows complete with 0% dependency on external network calls or cloud services.
- **SC-006**: The printable layout renders prescriber credentials, chamber banner, uppercase generic molecules, and verification seal without visual overlap or pagination breakage across standard A4 and thermal prescription formats.

## Assumptions

- **Single Active Edge Practitioner**: While a clinic device can configure multiple practice chambers, it represents a single primary prescribing physician at any given time for offline key storage.
- **Local Secret Storage**: The symmetric encryption key for the patient data vault (AES-256-GCM) is supplied via local application configuration or environment variables, avoiding any reliance on cloud Key Management Services (KMS).
- **Patient Vault Lookup**: Patient vault records can be retrieved by their local unique patient ID or matched via a privacy-preserving indexed search token without exposing sensitive phone numbers or names in plaintext indexes.
- **Chamber Snapshotting**: When a prescription is finalized, an immutable snapshot of the active chamber's details (name, address, schedule, contact) and doctor credentials is frozen with the prescription so that future modifications to chamber settings never alter past legal records.
- **Offline Operation**: The entire feature operates completely air-gapped on edge hardware in strict compliance with Article V and Article VIII of the RxGenerator Constitution.
