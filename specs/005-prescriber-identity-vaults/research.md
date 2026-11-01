# Research & Technical Decisions: Prescriber Identity, Multi-Chamber Management, and Encrypted Patient Vaults

**Feature**: `005-prescriber-identity-vaults`  
**Date**: 2026-11-01  
**Status**: Completed  

---

## 1. Protected Health Information (PHI) Vault & At-Rest Encryption Architecture

### Context & Requirements
Article VIII of the RxGenerator Constitution mandates that all Protected Health Information (`name`, `contact`, `clinical_notes`, `age`) MUST be encrypted at rest via Cloak / AES-GCM before writing to the local SQLite database. The user specifically requires:
- Use of `ash_cloak` with `Cloak` (AES-256-GCM cipher).
- Implementation of `RxGenerator.Vault` running under the OTP supervision tree.
- Transparent encryption on `Prescription` for `:patient_name`, `:patient_phone`, `:patient_age`, and `:clinical_notes`.
- Hard assertions that raw SQLite columns contain binary ciphertext with zero plaintext leakage.

### Decision 1: `RxGenerator.Vault` under OTP Supervision
- **Implementation**: Define `RxGenerator.Vault` using `use Cloak.Vault, otp_app: :rx_generator`.
- **Cipher**: `Cloak.Ciphers.AES.GCM` with a 256-bit (32-byte) key.
- **Key Bootstrap**: For zero-cloud edge deployments, the key is resolved in `init/1` from `System.get_env("RX_VAULT_KEY")`. In `:dev` and `:test` environments, if unconfigured, it automatically derives a deterministic 256-bit key (e.g. `:crypto.hash(:sha256, "rx_generator_edge_vault_master_key_2026")`) to avoid manual setup overhead while guaranteeing authenticated Galois/Counter Mode encryption.
- **Supervision**: Added as a permanent child in `RxGenerator.Application.start/2` preceding Ash resource initialization and endpoint startup.
- **Alternatives Considered**:
  - *SQLCipher*: Rejected because it requires custom SQLite C extensions and compiler toolchains, complicating cross-platform edge installs and risking database corruption during air-gapped updates.
  - *Plain Erlang `:crypto.crypto_one_time/5` in changesets*: Rejected because `ash_cloak` provides first-class declarative DSL integration with Ash resource calculations and migrations, preventing boilerplate and cipher leakage.

### Decision 2: Declarative Resource Encryption via `AshCloak`
- **Configuration**:
  ```elixir
  use Ash.Resource,
    otp_app: :rx_generator,
    domain: RxGenerator.Prescriptions,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshCloak, AshStateMachine]

  cloak do
    vault RxGenerator.Vault
    attributes [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    decrypt_by_default [:patient_name, :patient_phone, :patient_age, :clinical_notes]
    encrypt_nil? false
  end
  ```
- **Storage Mapping**: `AshCloak` automatically creates underlying attributes prefixed with `encrypted_` (`:encrypted_patient_name`, `:encrypted_patient_phone`, `:encrypted_patient_age`, `:encrypted_clinical_notes`) backed by `:binary` SQLite columns. The user-facing field names become Ash calculations that transparently decrypt values in memory when loaded.
- **Raw Storage Verification**: Automated test suites will query SQLite directly via Ecto SQL (`Repo.query!("SELECT encrypted_patient_name, encrypted_patient_phone, encrypted_patient_age, encrypted_clinical_notes FROM prescriptions")`) asserting that raw stored values are non-empty binaries whose string representations do NOT contain the plaintext values, proving cryptographic protection at rest.

---

## 2. Prescriber Identity and Multi-Chamber Data Architecture

### Context & Requirements
Physicians in Bangladesh frequently consult at multiple chambers (hospitals, diagnostic centers, private chambers) with distinct visiting hours, addresses, and contact numbers. Furthermore, BM&DC regulations demand that the doctor's name, qualifications, and registration number appear clearly on every prescription.

### Decision 3: Separation of `PrescriberProfile` and `ChamberConfig`
- **`PrescriberProfile`**: Represents the clinician's legal credentials.
  - Fields: `id` (UUID), `name` (string), `bmdc_no` (string, unique), `qualifications` (string, e.g., "MBBS (DMC), FCPS (Medicine)"), `specialty` (string, e.g., "Internal Medicine & Cardiologist"), `active` (boolean).
  - Validations: Enforces presence and format of `bmdc_no` (e.g. "A-12345" format) before activation.
- **`ChamberConfig`**: Represents an individual practice location.
  - Fields: `id` (UUID), `prescriber_profile_id` (belongs_to), `chamber_name` (string), `hospital_name` (string), `address` (string), `visiting_hours` (string), `contact_phone` (string), `is_default` (boolean), `active` (boolean).
  - Relationship: Belongs to `PrescriberProfile`.
- **Prescription Association & Snapshotting**:
  - `Prescription` holds `belongs_to :prescriber, PrescriberProfile` and `belongs_to :chamber, ChamberConfig`.
  - To honor Constitutional Article IX (Immutability), `Prescription` ALSO stores snapshot fields:
    - `prescriber_name`, `prescriber_bmdc_no`, `prescriber_qualifications`
    - `chamber_name`, `chamber_address`, `chamber_schedule`, `chamber_phone`
  - When a prescription transitions from `:draft` to `:locked`, these snapshots are permanently frozen. If the physician later updates chamber consultation hours or qualifications, historical issued prescriptions remain 100% historically and forensically accurate.

---

## 3. Dynamic LiveView Chamber Switcher & Canvas Integration

### Context & Requirements
The physician needs to seamlessly switch between practice chambers directly on the prescription canvas during active consultation, immediately updating the on-screen header and the print layout.

### Decision 4: Real-time LiveView Event Architecture
- **State Assigns**:
  - `@prescriber`: Active `PrescriberProfile` struct.
  - `@chambers`: List of configured `ChamberConfig` records for the active prescriber.
  - `@active_chamber`: Currently selected `ChamberConfig`.
- **Interaction**:
  - An interactive dropdown or segmented pill switcher renders in the canvas header when `@draft.state == :draft`.
  - Emits `phx-click="switch_chamber"` or `phx-change="select_chamber"` with `%{"chamber_id" => id}`.
  - LiveView updates socket assigns and calls `Prescriptions.set_prescription_chamber(draft, chamber_id)` to rebind the draft.
  - When `@draft.state == :locked`, the switcher is hidden or rendered as a static disabled badge.
- **Sub-15ms Latency SLA**:
  - Chamber switching executes entirely in-memory with local SQLite foreign key updates, meeting the < 15ms latency constraint of Article VI.

---

## 4. Cryptographic Binding to Ed25519 Signing Pipeline & Print Layout

### Context & Requirements
Under Constitutional Article X and User Story 4, the printed prescription must bind the active doctor credentials and chamber header to the Ed25519 cryptographic signing pipeline and print layout. The resulting QR code payload must remain compact (< 450 bytes for 10 line items) for 203 DPI thermal printing.

### Decision 5: Manifest V2 Format with Prescriber & Chamber Binding
- **Canonical Schema**:
  ```text
  v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>|<serialized_items...>
  ```
  - `chamber_token`: A normalized, URL-safe/alphanumeric identifier derived from the chamber name (or truncated 8-character UUID) to prevent QR optical density bloat.
  - Delimiter Sanitization: Delimiters `|`, `:`, and `#` are sanitized to `_`.
  - Byte Budget: The addition of `chamber_token` adds only 8–12 bytes to the canonical preimage. For a 10-item prescription, the total payload (`manifest#base64_sig`) remains ~385–395 bytes, well below the 450-byte thermal printing limit.
- **Signing & Verification**:
  - `Crypto.sign_manifest/2` signs the UTF-8 bytes of Manifest V2 using the doctor's offline private key.
  - `Crypto.verify_qr_payload/1` parses Manifest V2, verifies against the public key matching `prescriber_bmdc_no` in the provider registry, and returns `VerificationResult` containing prescriber and chamber metadata.

### Decision 6: High Court Compliant Print Layout (@media print)
- **Header Structure**:
  - Left / Main: Doctor Name (bold, prominent), Qualifications, Specialty, BM&DC Reg No.
  - Right: Chamber / Hospital Name, Full Address, Visiting Hours, Appointment/Emergency Phone.
  - Divider rule separating header from clinical body.
- **Medication Body**:
  - Uppercase generic molecules (`String.upcase(generic_name)`) in bold typography, adhering strictly to Article II.
  - Canonical Bengali directions (`1+0+1`, `খাবারের পর`).
- **Footer**:
  - Dynamic 2D QR code (`eqrcode` SVG) with detached signature.
  - Print styles hide omnibar, chamber switcher controls, and navigation buttons (`print:hidden`).

