# Interface Contract: Patient Data Vault & Cloak AES-256-GCM Encryption

**Feature**: `005-prescriber-identity-vaults`  
**Contract**: Patient Data Vault & Storage Invariants  
**Status**: Ready  

---

## 1. Cryptographic Primitive & Serialization

- **Engine**: `Cloak` 1.0 via `AshCloak` 0.4.
- **Cipher Module**: `Cloak.Ciphers.AES.GCM`.
- **Key Length**: 256 bits (32 bytes).
- **Initialization Vector (IV)**: 12-byte cryptographically secure random nonce generated per encryption operation.
- **Authentication Tag**: 16-byte GCM authentication tag appended to the ciphertext payload.
- **Ciphertext Header Tag**: `"AES.GCM.V1"`.

### Binary Layout of Encrypted Column
```text
+-----------------------+-------------------+--------------------+------------------------+
| Tag Header (variable) | IV Nonce (12 B)   | Ciphertext (var)   | Auth Tag (16 B)        |
| e.g. "AES.GCM.V1"     | (random bytes)    | (AES-256 payload)  | (Galois tag)           |
+-----------------------+-------------------+--------------------+------------------------+
```

---

## 2. Resource Mapping

| Logical Attribute (Calculated) | Backing SQLite Column (Encrypted) | Data Type | Plaintext Example | Storage Representation |
|---|---|---|---|---|
| `:patient_name` | `encrypted_patient_name` | `BLOB / binary` | `"Mst. Fatema Begum"` | `<<65, 69, 83, ...>>` |
| `:patient_phone` | `encrypted_patient_phone` | `BLOB / binary` | `"+8801812345678"` | `<<65, 69, 83, ...>>` |
| `:patient_age` | `encrypted_patient_age` | `BLOB / binary` | `"32Y 4M"` or `"32"` | `<<65, 69, 83, ...>>` |
| `:clinical_notes` | `encrypted_clinical_notes` | `BLOB / binary` | `"Complains of chest tightness & dyspnea"` | `<<65, 69, 83, ...>>` |

---

## 3. Storage Invariants & Verification Contract

### Invariant 1: Zero Plaintext in Database Files
When executing raw SQL against the SQLite database:
```sql
SELECT
  encrypted_patient_name,
  encrypted_patient_phone,
  encrypted_patient_age,
  encrypted_clinical_notes
FROM prescriptions
WHERE rx_number = ?;
```
1. No column may return text containing any substring of the original input.
2. The byte size of each encrypted column must be at least:
   `byte_size(Tag) + 12 (IV) + byte_size(plaintext) + 16 (Tag)`.
3. An offline scanner (e.g., `strings dev.db`) searching for the patient's name, phone, or clinical notes returns zero matching lines.

### Invariant 2: Transparent In-Memory Decryption
When loading a `Prescription` via Ash domain actions:
```elixir
{:ok, rx} = RxGenerator.Prescriptions.get_prescription(id)
assert rx.patient_name == "Mst. Fatema Begum"
assert rx.patient_phone == "+8801812345678"
assert rx.patient_age == "32"
assert rx.clinical_notes == "Complains of chest tightness & dyspnea"
```
Values are decrypted in memory using `RxGenerator.Vault` without altering the persisted binary ciphertexts.

