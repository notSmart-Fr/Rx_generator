# Quickstart & Verification Guide: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Feature Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14

This guide provides runnable test commands and verification scenarios proving the feature functions end-to-end according to all clinical and cryptographic specifications.

---

## 1. Prerequisites & Environment Setup

Ensure dependencies are resolved and test database is primed:

```bash
mix deps.get
mix test
```

---

## 2. Test Execution Suites

### Scenario 1: State Machine Immutability Gate

Verify that `:lock` transitions the prescription and permanently blocks all line item modifications, additions, or soft-deletions.

```bash
mix test test/rx_generator/prescriptions/immutability_test.exs
```

**Expected Result**:
- Attempts to modify items on a `:locked` prescription raise changeset errors.
- Attempts to finalize an empty draft prescription (0 items) fail validation.

---

### Scenario 2: Compact Manifest Serialization & Ed25519 Cryptography

Verify that the canonical manifest compiles deterministically, signs via `:crypto.sign(:eddsa, :none, ...)`, embeds into an SVG QR code, and verifies offline against the local BM&DC public key.

```bash
mix test test/rx_generator/prescriptions/crypto_test.exs
```

**Expected Result**:
- Compiles compact manifest payload strictly under 450 bytes for 10 line items.
- QR code renders valid scalable vector SVG.
- Decoded QR payload validates against doctor public key.
- Tampered payload (single bit flip) fails verification.

---

### Scenario 3: Property-Based Fuzz Testing (StreamData)

Run automated fuzz testing generating thousands of pseudo-random prescription structures to verify byte-level determinism and 100% tamper detection.

```bash
mix test test/rx_generator/prescriptions/manifest_fuzz_test.exs
```

**Expected Result**:
- Property 1: `serialize(rx) == serialize(rx)` holds across 500+ iterations.
- Property 2: Any mutation to the manifest or signature causes `verify/3` to return `false`.
- Property 3: Payload byte size remains < 450 bytes across 500+ generated prescriptions.

---

### Scenario 4: Dual-Dispatch Print Spooler (Mox Driver)

Verify that invoking print spooling dispatches to the hardware driver test double.

```bash
mix test test/rx_generator/printing/spooler_test.exs
```

**Expected Result**:
- `RxGenerator.Printing.MockSpooler` receives `spool/2` invocation with the finalized prescription record and options.

---

### Scenario 5: LiveView Interactive Finalization & Print Canvas

Verify the complete user journey in the Phoenix LiveView browser test:

```bash
mix test test/rx_generator_web/live/prescription_finalization_live_test.exs
```

**Expected Result**:
- User adds medications via omnibar.
- Clicking "Finalize Prescription" executes the `:lock` transition.
- Omnibar editing controls are removed / disabled.
- The canvas displays the generated QR code and "LOCKED & IMMUTABLE" badge.
- Generics appear in uppercase (`String.upcase(generic_name)`) and Bengali directions are visible.
- Clicking "Print" pushes the `"print_prescription"` event to the client.

---

## 3. Full Precommit Quality Gate

Run the complete suite to verify strict adherence to zero warnings, clean code formatting, and passing tests:

```bash
mix precommit
```
