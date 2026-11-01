# Interface Contract: Manifest V2 Format, Chamber Binding & Ed25519 Signing

**Feature**: `005-prescriber-identity-vaults`  
**Contract**: Manifest V2 & Cryptographic Digital Signature  
**Status**: Ready  

---

## 1. Manifest V2 Canonical Serialization

The canonical manifest binds the active prescriber credentials and chamber identity into the tamper-evident preimage before calculating the Ed25519 digital signature.

### Schema Specification
```text
v2|<rx_number>|<prescriber_bmdc_no>|<chamber_token>|<timestamp>|<serialized_item_1>|<serialized_item_2>|...
```

### Field Definitions

| Position | Field | Format / Constraints | Example |
|---|---|---|---|
| 0 | `version` | Constant `"v2"` | `v2` |
| 1 | `rx_number` | Alphanumeric prescription code, `_` for delimiters | `RX-20261101-ABCD` |
| 2 | `prescriber_bmdc_no` | BM&DC registration number, sanitized `|` and `:` | `A-12345` |
| 3 | `chamber_token` | Slug or 8-char prefix of chamber identifier, sanitized | `popular_dhanmondi` or `c_9b1deb4d` |
| 4 | `timestamp` | Integer seconds since Unix epoch (`DateTime.to_unix/2`) | `1793540000` |
| 5..N | `serialized_items` | `<short_drug_id>:<matrix>:<duration>:<timing>` | `9a8b7c6d:1+0+1:5d:pc` |

### Serialization Rules
1. **Delimiter Sanitization**: Any internal occurrences of `|` or `:` in fields are sanitized to `_`.
2. **Item Ordering**: Line items MUST be sorted strictly by `{item.display_order ASC, item.id ASC}` to guarantee 100% deterministic preimage generation across all OTP nodes.
3. **Active Items Only**: Items with `archived_at != nil` are strictly excluded.
4. **Drug ID Truncation**: Drug primary keys are truncated to 8 hexadecimal/alphanumeric characters.

---

## 2. 2D Barcode (QR Code) Payload

The QR code encodes the canonical manifest and its detached Ed25519 signature separated by a hash symbol (`#`):
```text
<manifest_v2_string>#<base64_ed25519_signature>
```

### Optical Density Budget (< 450 bytes)
For a 10-item prescription:
- `version`: 2 bytes
- `rx_number`: ~16 bytes
- `prescriber_bmdc_no`: ~8 bytes
- `chamber_token`: ~12 bytes
- `timestamp`: 10 bytes
- Separators: ~5 bytes
- 10 line items @ ~24 bytes: 240 bytes
- Delimiter `#`: 1 byte
- Base64 Ed25519 Signature: 88 bytes
- **Total Payload Size**: ~382 bytes

**Optical Verdict**: At ~382 bytes, the payload comfortably fits within QR Version 14 (EC Level L / M), remaining well below the 450-byte threshold and guaranteeing 100% legibility on 203 DPI thermal paper.

---

## 3. Cryptographic Verification Contract

### Verification Flow: `RxGenerator.Prescriptions.Crypto.verify_qr_payload/1`

```
   QR Payload: "v2|RX-001|A-12345|dhanmondi|1793540000|...#SIG_BASE64"
                            |
                            v
               Split payload by last '#'
                 /                   \
                v                     v
          Manifest V2         Base64 Signature
                |                     |
                v                     v
   Parse header: A-12345        Decode Base64 to 64 bytes
                |                     |
                v                     |
   Lookup A-12345 in local            |
   ProviderRegistry (ETS)             |
                |                     |
                v                     |
       Fetch 32-byte PubKey           |
                \                     /
                 v                   v
      :crypto.verify(:eddsa, :none, manifest, sig, [pub_key, :ed25519])
                            |
             +--------------+--------------+
             |                             |
          true                           false
             |                             |
             v                             v
   {:ok, %VerificationResult{     {:error, %VerificationResult{
     valid?: true,                  valid?: false,
     prescriber_bmdc_no: "A-12345", status: :signature_mismatch
     chamber: "dhanmondi", ...}}    error_message: "Tamper detected"}}
```

