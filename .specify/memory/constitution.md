<!--
Sync Impact Report:
- Version change: Unratified Draft (1.0.0-template) → 1.0.0
- List of modified principles:
  - [PRINCIPLE_1_NAME] → Article I — Zero Hallucination Boundary
  - [PRINCIPLE_2_NAME] → Article II — High Court Generic Mandate
  - [PRINCIPLE_3_NAME] → Article III — The Human-in-the-Loop (HITL) Absolute
  - [PRINCIPLE_4_NAME] → Article IV — Controlled Substances Lockout
  - [PRINCIPLE_5_NAME] → Article V — Zero-Cloud Edge Autonomy
- Added sections:
  - Core Principles (Articles I through V)
  - Architectural & Runtime Constraints (Articles VI and VII)
  - Data Privacy & Cryptographic Immutability (Articles VIII, IX, and X)
  - Behavior-Driven & Test-Driven Development (BDD / TDD Invariants)
- Removed sections:
  - Generic template placeholder text
- Follow-up TODOs: None
-->

# RxGenerator Constitution: Edge-Native Clinical Prescription Engine (eRx)

## Core Principles

### Article I — Zero Hallucination Boundary
Generative models, LLMs, or heuristic predictors MUST NEVER generate dosages, active drug ingredients, or medication names directly into the clinical prescription record. All medication choices must resolve to an exact, deterministic primary key in the verified local Directorate General of Drug Administration (DGDA) database snapshot.

*Rationale*: Clinical safety demands absolute determinism in pharmacological entities; speculative generative outputs pose lethal risks in automated prescribing.

### Article II — High Court Generic Mandate
Prescriptions MUST print and display the active generic molecule name in bold, uppercase typography (`String.upcase(generic_name)`) with equal or greater visual prominence than any commercial brand name, strictly adhering to Bangladesh High Court directives.

*Rationale*: Compliance with national regulatory standards prevents commercial brand favoritism and safeguards patient affordability and transparency.

### Article III — The Human-in-the-Loop (HITL) Absolute
No algorithmic warning, drug-drug interaction (DDI) alert, or stewardship recommendation may automatically alter, substitute, or remove a prescription item without explicit human physician acknowledgment or override. The prescribing physician holds sole medical-legal accountability under the Bangladesh Medical and Dental Council (BM&DC).

*Rationale*: Legal liability and final clinical judgment reside exclusively with licensed practitioners; systems assist and inform but never usurp physician agency.

### Article IV — Controlled Substances Lockout
Regulated narcotics under the Narcotics Control Act 2018 MUST NOT be prescribed via remote or unverified workflows. Telemedicine issuance of Class-A narcotics is blocked at the Ash resource validation layer.

*Rationale*: Prevents illicit diversion and enforces strict regulatory safeguards for controlled pharmaceuticals at the domain validation boundary.

### Article V — Zero-Cloud Edge Autonomy
The core clinical loop (typing, shorthand expansion, entity resolution, interaction validation, and printing) MUST operate completely air-gapped without an internet connection, third-party cloud APIs, or external system daemons.

*Rationale*: Rural clinics and low-connectivity medical outposts require 100% operational reliability regardless of network availability.

## Architectural & Runtime Constraints

### Article VI — Memory & Performance Ceilings
* Active memory overhead for the local inference and execution engine MUST remain under 250MB RAM on standard commodity PC hardware.
* Autocomplete shorthand resolution and LiveView socket DOM patches MUST achieve round-trip latencies under 15ms.

*Rationale*: Doctors prescribe under high-throughput patient loads on low-spec clinic computers; sluggish interfaces induce workflow abandonment.

### Article VII — Two-Tier Entity Resolution
1. **Primary Tier**: Deterministic SQLite FTS5 trigram search against brand names.
2. **Fallback Tier**: Local vector similarity (via Nx + EmbeddingGemma 2 truncated to 256 dimensions using Matryoshka Representation Learning) ONLY when text search confidence falls below threshold.
3. **Presentation Filter**: Candidate vectors MUST always be constrained by clinical dosage form hints (`Tab`, `Syr`, `Cap`, `Inj`) to prevent cross-presentation formulation errors.

*Rationale*: Balances blazing speed on exact/fuzzy brand lookups with intelligent phonetic/typo resolution while strictly enforcing anatomical delivery forms.

## Data Privacy & Cryptographic Immutability

### Article VIII — Encryption-at-Rest for Protected Health Information (PHI)
Patient identifying attributes (`name`, `contact`, `clinical_complaints`) MUST be encrypted at rest via Cloak / AES-GCM before writing to the local SQLite database. Public drug catalogs and reference formularies remain unencrypted for fast FTS5 index scanning.

*Rationale*: Enforces medical confidentiality and data protection in case clinical hardware is stolen or inspected by unauthorized personnel.

### Article IX — State Machine Invariance
* A prescription in `:draft` state permits mutations and modifications.
* A prescription transitioned to `:locked` is permanently immutable. No updates or deletions are permitted on a locked record under any circumstances.
* Prescriptions MUST NEVER be hard-deleted from disk; soft archival (`ash_archival`) and audit logging (`ash_paper_trail`) MUST be maintained for legal accountability.

*Rationale*: Medical records require tamper-evident immutability and complete forensic traceability under BM&DC guidelines.

### Article X — Offline Authenticity
Printed prescriptions MUST embed an offline-verifiable SHA-256 or asymmetric digital signature in a 2D QR code payload (`BMDC_NO || DATE || RX_ID || DRUG_IDS`) to prevent unauthorized dispensary tampering.

*Rationale*: Pharmacies must be able to verify authenticity and integrity without requiring an online centralized lookup.

## Behavior-Driven & Test-Driven Development (BDD / TDD)

### Test-First Implementation Invariant (NON-NEGOTIABLE)
All clinical business rules, validation gates, interaction verifications, and state machine transitions MUST follow strict Test-Driven Development (TDD):
1. **Test Specification**: Feature specifications must be defined in executable behavioral tests (`Phoenix.LiveViewTest`, `ExUnit`, and Ash resource action tests) before implementing production logic.
2. **Red-Green-Refactor**: Tests must fail first, demonstrating the absence or boundary violation of the invariant, before the minimal compliant implementation is written.
3. **Clinical Invariant Regression Gate**: Every Pull Request and commit must pass automated checks confirming Articles I through X cannot be bypassed. Specifically:
   - Attempting to bypass the DGDA primary key foreign key relation in a prescription item fails unit tests.
   - Attempting to update or delete an item on a `:locked` prescription raises an immutable transition error.
   - Prescribing a Class-A narcotic via an unverified or telemedicine actor raises a forbidden validation error.
   - Cloak-encrypted fields are asserted to exist as binary ciphertexts on raw SQLite queries.
   - LiveView interaction benchmarks enforce rendering and resolution response limits.

## Governance

1. **Constitutional Precedence**: This constitution supersedes all other architectural discussions, transient design choices, and code conventions in the `RxGenerator` project.
2. **Amendment Procedure**: Amendments require formal RFC documentation, clinical safety justification, migration impact analysis, and explicit sign-off from clinical and technical stewards.
3. **Compliance Review**: All Pull Requests and automated builds must execute `mix precommit` and verification test suites to prove adherence to these constitutional invariants.

**Version**: 1.0.0 | **Ratified**: 2026-10-13 | **Last Amended**: 2026-10-13
