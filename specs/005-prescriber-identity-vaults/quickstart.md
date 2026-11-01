# Quickstart & Verification Guide: Prescriber Identity, Multi-Chamber Management, and Encrypted Patient Vaults

**Feature**: `005-prescriber-identity-vaults`  
**Date**: 2026-11-01  
**Status**: Ready  

---

## Prerequisites

1. Elixir ~> 1.17, Erlang/OTP 27+
2. Local dependencies installed: `mix deps.get`
3. SQLite3 database setup: `mix ash.setup`
4. Master vault key configured (defaults automatically in dev/test via `RxGenerator.Vault`).

---

## 1. Automated Test Suites (BDD / TDD Protocol)

To validate the implementation in strict compliance with the RxGenerator Constitution's Strict Test-First Protocol:

### Run Prescriber Profile & Multi-Chamber Tests
```powershell
mix test test/rx_generator/prescriptions/prescriber_chamber_test.exs
```
**Expected Outcome**:
- Asserts creation and validation of `PrescriberProfile` with BM&DC registration format checks.
- Asserts configuring multiple chambers for a single physician with default flag toggles.
- Asserts chamber switching on draft prescriptions and rejects switching on locked prescriptions.

### Run AshCloak At-Rest SQLite Encryption Tests
```powershell
mix test test/rx_generator/prescriptions/patient_vault_encryption_test.exs
```
**Expected Outcome**:
- Creates prescriptions with sensitive patient data (`patient_name`, `patient_phone`, `patient_age`, `clinical_notes`).
- Inspects SQLite raw storage via direct Ecto queries (`Repo.query!/2`), confirming binary ciphertext starting with `"AES.GCM.V1"`.
- Confirms zero plaintext matches in raw SQLite database files.
- Asserts transparent in-memory decryption when loaded through Ash domain actions.

### Run Manifest V2 & Cryptographic Signing Tests
```powershell
mix test test/rx_generator/prescriptions/manifest_v2_signing_test.exs
```
**Expected Outcome**:
- Verifies Manifest V2 compilation including prescriber BM&DC number and chamber token.
- Validates that total QR code payload remains < 450 bytes across 10 medication line items.
- Asserts detached Ed25519 signature verification against the doctor's public key.
- Asserts 100% signature rejection if chamber token or prescriber registration is modified post-signing.

### Run LiveView Chamber Switcher & Print Layout Tests
```powershell
mix test test/rx_generator_web/live/prescription_live/chamber_switcher_test.exs
```
**Expected Outcome**:
- Verifies that `PrescriptionLive` renders doctor credentials and active chamber banner on mount.
- Asserts clicking or selecting a chamber sends `switch_chamber` and dynamically patches the canvas header.
- Asserts that `@media print` layout displays the active doctor and chamber header alongside uppercase generic drug names while hiding omnibars and switcher UI.

---

## 2. Interactive Manual Verification Walkthrough

1. **Start the Phoenix Server**:
   ```powershell
   mix phx.server
   ```
2. **Access Prescription Interface**:
   - Open browser at `http://localhost:4000/`.
3. **Verify Prescriber & Chamber Header**:
   - Observe physician credentials (e.g. "Dr. Tariqul Islam, MBBS (DMC), FCPS", BM&DC "A-12345") displayed at the header.
   - Observe active chamber header (e.g. "Popular Diagnostic Centre, Dhanmondi").
4. **Switch Practice Chamber**:
   - Click the chamber dropdown/switcher and select "City Hospital Consultation Centre".
   - Notice immediate header update without page reload or loss of current prescription draft state.
5. **Enter Encrypted Patient Details**:
   - Fill in patient name, phone number, age, and clinical notes.
6. **Add Medications & Finalize**:
   - Type medication shorthand into omnibar (`napa 1+0+1 5d`).
   - Click **Finalize Prescription**.
   - Observe tamper-evident QR code rendered at canvas footer.
   - Notice chamber switcher becomes locked and disabled.
7. **Inspect Print Preview**:
   - Click **Print Prescription** or press `Ctrl + P`.
   - Verify print layout shows selected chamber banner and doctor qualifications, bold uppercase generic drug name, and hides omnibars and controls.
8. **Verify SQLite At-Rest Encryption**:
   - Open terminal and run:
     ```powershell
     mix run -e "IO.inspect(RxGenerator.Repo.query!(\"SELECT encrypted_patient_name FROM prescriptions\"))"
     ```
   - Confirm output displays raw binary ciphertext `<<65, 69, 83, ...>>`.

