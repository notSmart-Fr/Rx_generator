# Contract: Canonical Prescription Manifest & Cryptographic QR Payload

**Feature Branch**: `003-prescription-finalization-print` | **Date**: 2026-10-14 (Hardened)

## 1. Optical QR Code Payload Specification

To satisfy the **< 450 bytes** optical density ceiling on 203 DPI thermal printers, the QR code encodes a single ASCII string formatted as:

```text
<CANONICAL_MANIFEST>#<BASE64_SIGNATURE>
```

### Grammar

```abnf
QR-PAYLOAD        = MANIFEST "#" SIGNATURE
MANIFEST          = VERSION "|" RX-NUMBER "|" BMDC-NO "|" TIMESTAMP "|" ITEMS
VERSION           = "v1"
RX-NUMBER         = "RX-" 8DIGIT "-" 4HEXDIG
BMDC-NO           = ("A" / "B" / "D") "-" 1*6DIGIT
TIMESTAMP         = 10DIGIT ; Unsigned 64-bit integer: DateTime.to_unix(finalized_at, :second)
ITEMS             = ITEM *("|" ITEM)
ITEM              = DRUG-ID ":" MATRIX ":" DURATION ":" TIMING
DRUG-ID           = 8HEXDIG ; binary_part(drug_catalog_item_id, 0, 8)
MATRIX            = 1*6(DIGIT / "+" / "/" / "_")
DURATION          = 1*6(DIGIT / ALPHA / "_")
TIMING            = 1*6(ALPHA / "_")
SIGNATURE         = 86*88(ALPHA / DIGIT / "+" / "/" / "=")
```

### Delimiter Sanitization Invariant

Before serialization:
- Field values (`rx_number`, `bmdc_no`, `matrix`, `duration`, `timing`) MUST strip or replace any internal pipe `|` or colon `:` characters with underscore `_`:
  ```elixir
  def sanitize_token(str) when is_binary(str) do
    String.replace(str, ~r/[|:]/, "_")
  end
  ```
- This prevents delimiter collisions and ensures token parsing during QR verification is 100% boundary-stable.

### Example Valid Payload

```text
v1|RX-20261014-9B2F|A-12345|1760424000|a1b2c3d4:1+0+1:5d:pc|e5f6a7b8:0+0+1:14d:hs#u+2K...base64_sig...==
```

### Byte Budget Analysis (10-Item Prescription)

| Component | Example Value | Estimated Bytes |
|:---|:---|:---|
| Header (`VERSION\|RX\|BMDC\|TIME\|`) | `v1\|RX-20261014-9B2F\|A-12345\|1760424000\|` | ~45 bytes |
| 10 Line Items | 10 × `a1b2c3d4:1+0+1:14d:pc\|` | 10 × ~24 = ~240 bytes |
| Delimiter (`#`) | `#` | 1 byte |
| Ed25519 Detached Signature (Base64) | 64 bytes binary Base64-encoded | 88 bytes |
| **Total Payload Size** | | **~374 bytes** |

**Conclusion**: 374 bytes is well within the 450-byte threshold, comfortably fitting into QR Version 9 with Error Correction Level M.

---

## 2. Cryptographic Preimage Ordering & Verification Contract

### Manifest Signing Pipeline

```mermaid
flowchart LR
    A[Prescription + Items] -->|Sort display_order ASC, then id ASC| B[Compile Manifest String]
    B -->|Sanitize Delimiters + Epoch Seconds| C[canonical_string]
    C -->|UTF-8 Bytes| D[manifest_bytes]
    D -->|:crypto.sign :eddsa, :none, bytes, [priv_key, :ed25519]| E[64-byte Binary Signature]
    E -->|Base.encode64| F[Base64 Signature String]
    C & F -->|Join with #| G[Final QR Payload]
```

### Verification Pipeline

```mermaid
flowchart LR
    A[Scanned QR Payload] -->|Split on #| B[Manifest String] & C[Base64 Signature]
    B -->|Parse BM&DC No| D[Lookup Public Key in Local BM&DC Snapshot]
    C -->|Base.decode64| E[Binary Signature]
    B -->|UTF-8 Bytes| F[manifest_bytes]
    D & E & F -->|:crypto.verify :eddsa, :none, bytes, sig, [pub_key, :ed25519]| G{Valid?}
    G -->|true| H[Return :ok, Verified Struct]
    G -->|false| I[Return :error, :signature_mismatch]
```

### Public API Contract: `RxGenerator.Prescriptions.Crypto`

```elixir
defmodule RxGenerator.Prescriptions.Crypto do
  @doc "Signs a canonical manifest string using the doctor's Ed25519 private key."
  @spec sign_manifest(String.t(), binary()) :: {:ok, String.t()} | {:error, term()}

  @doc "Verifies a canonical manifest against a signature and Ed25519 public key."
  @spec verify_manifest(String.t(), String.t(), binary()) :: boolean()

  @doc "Encodes the signed manifest into a QR payload string."
  @spec build_qr_payload(String.t(), String.t()) :: String.t()

  @doc "Parses and verifies a QR payload against the local provider registry snapshot."
  @spec verify_qr_payload(String.t()) :: RxGenerator.Prescriptions.VerificationResult.t()
end
```
