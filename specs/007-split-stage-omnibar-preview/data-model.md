# Data Model: Two-Column Clinical Prescription Workspace & Real-Time A4 Paper Preview

**Feature**: `007-split-stage-omnibar-preview`  
**Date**: 2026-11-17  
**Status**: Ready  

---

## 1. Existing AshSqlite Resources (Zero Schema Migration Required)

All data persists through the existing `AshSqlite` resources in `RxGenerator.Prescriptions` and `RxGenerator.Formulary`:

```text
+-------------------------------------------------------------------+
|                           Prescription                            |
+-------------------------------------------------------------------+
| id: uuid (PK)                                                     |
| rx_number: string (unique)                                        |
| state: :draft | :locked                                           |
| prescriber_profile_id: uuid (FK -> PrescriberProfile)             |
| chamber_config_id: uuid (FK -> ChamberConfig)                     |
|                                                                   |
| [AshCloak AES-256-GCM Encrypted Attributes]                       |
| - patient_name (encrypted_patient_name: binary)                   |
| - patient_phone (encrypted_patient_phone: binary)                 |
| - patient_age (encrypted_patient_age: binary)                     |
| - clinical_notes (encrypted_clinical_notes: binary)               |
|   * Encodes: left_margin_notes ("\n===ADVICE===\n") general_advice|
|                                                                   |
| [Snapshots & Ed25519 Seal]                                        |
| - prescriber_name, prescriber_bmdc_no, prescriber_qualifications  |
| - chamber_name, chamber_address, chamber_schedule, chamber_phone  |
| - canonical_manifest, signature, finalized_at                     |
+-------------------------------------------------------------------+
                                 | 1
                                 | has_many :items
                                 v *
+-------------------------------------------------------------------+
|                         PrescriptionItem                          |
+-------------------------------------------------------------------+
| id: uuid (PK)                                                     |
| prescription_id: uuid (FK -> Prescription)                        |
| drug_catalog_item_id: uuid (FK -> DrugCatalogItem)                |
| brand_name_snapshot: string                                       |
| generic_name_snapshot: string                                     |
| dosage_form_snapshot: string                                      |
| strength_snapshot: string                                         |
| is_controlled_snapshot: boolean                                   |
| dosage_matrix: string ("1+0+1", "1+1+1", "1+0+0", "0+0+1",        |
|                        "1 tsp", "SOS", "as_directed")             |
| duration_expression: string ("3 days", "5 days", "7 days",        |
|                              "14 days", "30 days", "continue")    |
| timing_instruction: string ("pc", "ac", "empty", "hs", "sos",     |
|                             or "<code>; <free_text_note>")        |
| canonical_bengali_text: string                                    |
| bengali_breakdown_text: string ("সকাল ১, দুপুর ০, রাত ১")         |
| display_order: integer                                            |
| archived_at: utc_datetime_usec (AshArchival soft-delete)          |
+-------------------------------------------------------------------+
```

---

## 2. Value Objects & Helper Projections

### 2.1 One-Tap Rx Card Controls (`RxGenerator.Prescriptions.SmartDefaults`)
- **Dose Presets**: `["1+0+1", "1+1+1", "1+0+0", "0+0+1", "1 tsp", "SOS"]`
- **Timing Presets**:
  - `{"pc", "After meal", "ভরা পেটে"}`
  - `{"ac", "30 mins before meal", "খাবার ৩০ মিনিট আগে"}`
  - `{"empty", "Empty stomach", "খালি পেটে"}`
  - `{"hs", "Bedtime", "ঘুমানোর আগে"}`
- **Duration Presets**:
  - `{"3 days", "3d", "৩ দিন"}`
  - `{"5 days", "5d", "৫ দিন"}`
  - `{"7 days", "7d", "৭ দিন"}`
  - `{"14 days", "14d", "১৪ দিন"}`
  - `{"30 days", "30d", "৩০ দিন"}`
  - `{"continue", "Continue", "চলবে"}`

### 2.2 Left-Margin Clinical Notes & General Advice Encoding
- Stored inside `Prescription.clinical_notes` (encrypted at rest via `AshCloak`):
  - **Clinical Prefix Helpers**: `["C/C", "O/E", "Dx", "Ix"]`
  - **General Advice Bengali Chips**:
    - `"পর্যাপ্ত পানি পান করবেন"`
    - `"নিয়মিত ওষুধ সেবন করবেন"`
    - `"ঠান্ডা ও ধুলাবালি এড়িয়ে চলুন"`
    - `"৭ দিন পর দেখা করবেন"`
    - `"জ্বর ১০১° ফারেনহাইটের বেশি হলে প্যারাসিটামল খাবেন"`
