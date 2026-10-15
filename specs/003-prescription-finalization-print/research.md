# Architectural Research & Technical Decisions: Prescription Finalization, Offline Cryptographic Verification, and Print Spooling

**Feature Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14 (Hardened)

## Context & Objectives

This document evaluates the architectural, cryptographic, and hardware constraints for finalization, offline asymmetric signing, optical QR density ceilings, print rendering, and testing for the edge-native RxGenerator engine.

---

## Technical Decisions

### Decision 1: Cryptographic Engine — Erlang Native `:crypto` (:ed25519)

- **Decision**: Use Erlang/OTP native `:crypto.sign(:eddsa, :none, manifest_bytes, [private_key, :ed25519])` and `:crypto.verify(:eddsa, :none, manifest_bytes, signature_bytes, [public_key, :ed25519])`.
- **Rationale**:
  - Ed25519 (EdDSA over Curve25519) provides high security (128-bit security level) with minimal signature (64 bytes) and public key (32 bytes) sizes.
  - Asymmetric keys ensure non-repudiation: only the prescribing doctor possessing the offline private key can produce a valid signature, while any pharmacist or audit agent can verify authenticity using the public key from the local BM&DC snapshot.
  - Zero external hex dependencies required; `:crypto` is built directly into the BEAM runtime.
  - Signature verification runs in < 1ms on edge hardware.
- **Alternatives Considered**:
  - *HMAC-SHA256 (Symmetric)*: Rejected because verification requires knowing the signing key; sharing secret keys with pharmacies destroys non-repudiation and enables prescription forgery.
  - *RSA-2048 / RSA-4096*: Rejected because signatures (256–512 bytes) would bloat the QR payload beyond optical density scanning limits on thermal paper.
  - *External Cloud KMS / Signing APIs*: Strictly prohibited by Article V (Zero-Cloud Edge Autonomy) and Article X (Offline Authenticity).

---

### Decision 2: Compact Manifest Serialization Schema (< 450 Bytes Ceiling)

- **Decision**: Define a compact, versioned, delimited text schema for the canonical prescription manifest. Line items are strictly ordered by `display_order ASC, then id ASC`, and fields are concatenated into a UTF-8 string:
  ```text
  v1|<rx_number>|<prescriber_bmdc_no>|<unix_timestamp>|<item_1>|<item_2>|...|<item_n>
  ```
  Where:
  1. `unix_timestamp` is an integer: `DateTime.to_unix(finalized_at, :second)`.
  2. Each line item is compactly encoded:
     `<short_drug_id>:<sanitized_matrix>:<sanitized_duration>:<sanitized_timing>`
  3. `short_drug_id` is the first 8 characters of `drug_catalog_item_id` (`binary_part(id, 0, 8)`).
  4. Delimiter Sanitization: Internal pipe `|` and colon `:` characters in any field are stripped or replaced with `_` before serialization to prevent token offset corruption.
  Example:
  ```text
  v1|RX-20261014-9B2F|A-12345|1760424000|a1b2c3d4:1+0+1:5d:pc|e5f6a7b8:0+0+1:14d:hs
  ```
- **Rationale**:
  - A standard 2D QR code printed on a 203 DPI thermal printer or rough paper degrades rapidly if the payload exceeds 500 bytes.
  - The compact delimited format ensures a 10-item prescription consumes ~374 bytes (staying strictly under **450 bytes**, fitting QR Version 9 with Level M error correction).
  - Preimage sorting invariance: Sorting items strictly by `display_order ASC` and using fixed UTF-8 bytes guarantees 100% signature verification reproducibility across all BEAM nodes.
- **Alternatives Considered**:
  - *JSON*: Rejected due to key verbosity bloating QR optical density (> 1,200 bytes).
  - *Full 36-char UUIDs*: 10 items would consume 360 bytes on IDs alone; 8-char prefixes provide collision safety within a prescription while saving ~280 bytes.

---

### Decision 3: Embedded QR Code Generation via `eqrcode`

- **Decision**: Use `eqrcode` (embedded pure Elixir QR generator) to produce vector SVG strings rendered directly within Phoenix LiveView HEEx templates.
- **Rationale**:
  - Pure Elixir implementation with zero native C dependencies or ImageMagick system binaries.
  - Generates vector SVGs that scale crisply on any printer resolution (203 DPI thermal up to 1200 DPI laser) without pixelation or scanning artifacts.
  - Server-side rendering ensures the QR code is immediately available in the DOM before `window.print()` triggers, preventing client-side canvas rendering race conditions.
- **Alternatives Considered**:
  - *Client-side JavaScript canvas QR libraries*: Rejected because client rendering introduces asynchronous timing issues when automated print spooling triggers immediately after finalization.
  - *Server-side PNG/Bitmap generation*: PNG bitmaps rasterize at a fixed DPI and blur when scaled on high-resolution printers.

---

### Decision 4: Immutability State Machine & Multi-Layer Domain Validation

- **Decision**: 
  1. `Prescription` uses `AshStateMachine` to transition from `:draft` to `:locked` via the `:lock` action.
  2. The `:lock` action enforces:
     - State must currently be `:draft`.
     - Prescription must contain at least one line item (`items != []`).
     - Atomically sets `canonical_manifest`, `signature`, and `finalized_at = DateTime.utc_now()`.
  3. `PrescriptionItem` validates parent immutability via `ParentIsDraft` validation on `[:create, :update, :destroy]`. It extracts `changeset.data.prescription_id` or `Ash.Changeset.get_attribute(changeset, :prescription_id)` and evaluates against the parent prescription's database state to ensure `destroy` actions cannot delete items on locked prescriptions.
  4. Database integrity: Unique index on `prescriptions(rx_number)` ensures no duplicate prescriptions can exist.
- **Rationale**:
  - Satisfies Article IX (State Machine Invariance) and Article III (HITL).
  - Guarantees medical-legal non-repudiation: line items cannot be swapped, updated, or soft-deleted after signing.
- **Alternatives Considered**:
  - *Database-level triggers*: Harder to maintain, test in-memory, and less transparent to the Ash domain layer.

---

### Decision 5: Dual-Dispatch Printing Architecture & Mox Test Double

- **Decision**:
  - **Client-Side Interactive**: LiveView pushes event `print_prescription` to a client JS Hook triggering `window.print()`. Clean `@media print` CSS rules in `app.css` isolate the canvas, hide omnibar/HUD elements, and enforce High Court typography.
  - **Backend Headless Spooler**: Define `RxGenerator.Printing.Spooler` behaviour:
    ```elixir
    defmodule RxGenerator.Printing.Spooler do
      @callback spool(prescription :: Prescription.t(), opts :: keyword()) :: :ok | {:error, term()}
    end
    ```
    With an edge driver `RxGenerator.Printing.OSSpooler` and a `Mox` test double `RxGenerator.Printing.MockSpooler` defined in `test/support/mocks.ex`.
- **Rationale**:
  - Interactive doctor consultation workflows require the familiar browser print preview dialog.
  - Automated integration tests, CI pipelines, and unattended thermal kiosks require headless execution verified via `Mox` without physical printers attached.
- **Alternatives Considered**:
  - *Browser-only printing*: Cannot be verified in automated server-side test suites.
  - *Backend CLI-only printing (`lp / lpr`)*: Fails on client machines that operate as remote web clients to an edge server without local CUPS configuration.

---

### Decision 6: Property-Based Fuzz Testing with `StreamData`

- **Decision**: Implement property tests (`RxGenerator.Prescriptions.ManifestFuzzTest`) using `StreamData`:
  1. **Determinism Property**: For any valid generated prescription and item list, `compile_manifest/1` produces the exact same binary payload across repeated executions.
  2. **Tamper Detection Property**: For any valid signed manifest, flipping any single bit, changing any digit in dosage or date, or inserting whitespace causes `:crypto.verify/5` to return `false`.
  3. **Optical Density Property**: For any generated prescription with up to 10 medication line items, the generated payload byte size is guaranteed to be `< 450 bytes`.
- **Rationale**:
  - Proves cryptographic soundness and optical density guarantees across thousands of edge-case inputs before shipping to clinic hardware.

---

### Decision 7: Doctor Identity & Keypair Bootstrapping

- **Decision**: In development and test environments (`Mix.env() in [:dev, :test]`), if a physician signing key is not found in `priv/keys/doctor_signing_key.pem`, the system automatically bootstraps a deterministic Ed25519 keypair and registers the public key into the local provider registry snapshot. In production (`Mix.env() == :prod`), missing keys trigger a clear administrative configuration error.
- **Rationale**:
  - Prevents friction in dev/test workflows while maintaining strict cryptographic boundaries in production.
