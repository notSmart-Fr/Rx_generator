# Interface Contract: LiveView Chamber Switcher & Canvas Header

**Feature**: `005-prescriber-identity-vaults`  
**Contract**: Chamber Switcher & Prescription Canvas Header  
**Status**: Ready  

---

## 1. LiveView Component Assigns & State

The `PrescriptionLive` LiveView maintains the following state assigns related to prescriber identity and practice chambers:

| Assign | Type | Description |
|---|---|---|
| `@prescriber` | `RxGenerator.Prescriptions.PrescriberProfile.t() \| nil` | The active licensed physician profile. |
| `@chambers` | `[RxGenerator.Prescriptions.ChamberConfig.t()]` | List of all active practice chambers for `@prescriber`. |
| `@active_chamber` | `RxGenerator.Prescriptions.ChamberConfig.t() \| nil` | Currently selected chamber for the active prescription. |
| `@draft` | `RxGenerator.Prescriptions.Prescription.t()` | The current active draft prescription. |

---

## 2. Interactive Events (Client -> Server)

### Event: `switch_chamber`
- **Trigger**: User clicks a chamber tab/pill or selects an option from the chamber switcher dropdown on the prescription canvas.
- **Payload**:
  ```json
  {
    "chamber_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
  }
  ```
- **Server Guard**:
  - If `@draft.state == :locked`: Ignored with a flash warning or no-op.
  - If `@draft.state == :draft`:
    - Validates that `chamber_id` belongs to `@chambers`.
    - Updates `@draft` association via `RxGenerator.Prescriptions.set_prescription_chamber(@draft, chamber_id)`.
    - Reassigns `@active_chamber` in socket.
    - Re-renders canvas header with immediate DOM patch (< 15ms SLA).

### Event: `update_patient_vault`
- **Trigger**: Physician enters or edits patient demographic and clinical information on the canvas.
- **Payload**:
  ```json
  {
    "patient_name": "Rahim Uddin",
    "patient_phone": "01712345678",
    "patient_age": "48",
    "clinical_notes": "Follow-up for type 2 diabetes and hypertension"
  }
  ```
- **Server Guard**:
  - Validates draft state.
  - Updates draft via `RxGenerator.Prescriptions.update_patient_details(@draft, params)`.
  - Encrypts at rest through `AshCloak` transparently.

---

## 3. DOM Elements and Selectors

| Element ID | Tag / Class | Purpose |
|---|---|---|
| `#chamber-switcher` | `div.chamber-switcher-container` | Container for chamber selection controls (hidden when locked or during print). |
| `#chamber-select-dropdown` | `select` or `div.pill-group` | Dropdown or buttons emitting `phx-click="switch_chamber"` or `phx-change="switch_chamber"`. |
| `#canvas-prescriber-name` | `h1.font-black` | Displays doctor's name on canvas header. |
| `#canvas-prescriber-bmdc` | `span.font-mono` | Displays BM&DC registration number. |
| `#canvas-prescriber-qualifications` | `p.text-xs` | Displays doctor's medical degrees and specialties. |
| `#canvas-chamber-name` | `h3.font-bold` | Displays selected chamber clinic/hospital name. |
| `#canvas-chamber-address` | `p.text-xs` | Displays chamber physical address. |
| `#canvas-chamber-schedule` | `span.text-xs` | Displays visiting hours and consultation days. |
| `#canvas-chamber-phone` | `span.font-mono` | Displays appointment/emergency phone number. |
| `#patient-vault-fields` | `div.patient-vault-section` | Form or display inputs for patient demographic & clinical details. |

---

## 4. Print Layout Specifications (`@media print`)

In print mode:
1. `#chamber-switcher` and any interactive form inputs are hidden (`print:hidden`).
2. `#prescription-omnibar` is hidden (`print:hidden`).
3. Prescription header displays a structured 2-column medical prescription banner:
   - **Left Column**: Doctor's full name, BM&DC registration number, qualifications, and specialties.
   - **Right Column**: Clinic / Chamber name, street address, consulting hours, contact numbers.
4. Below the banner, a clean horizontal rule separates provider credentials from the Rx medication table and clinical notes.
5. Generic molecule names remain bold uppercase (`String.upcase(generic_name)`) adhering to High Court mandates.
6. The verification seal QR code renders at the footer with tamper-evident Ed25519 signatures.

