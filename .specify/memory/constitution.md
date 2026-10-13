<!--
Sync Impact Report:
- Version change: 1.1.0 → 1.2.0
- List of modified principles:
  - Article VI — Memory & Performance Ceilings: Added cold-boot asynchronous compilation SLA for EXLA/Nx model warming.
  - Article VII — Two-Tier Entity Resolution: Added pharmacological lexing invariance (DFA/token stream preserving strength indicators).
  - Article X — Offline Authenticity: Upgraded from plain checksum to detached asymmetric Ed25519 digital signature with offline BM&DC public key validation.
  - Governance: Added Agentic Scope & Modification Fence prohibiting unauthorized Hex dependencies, DB adapter changes, or cloud network driver additions during /speckit workflows.
- Added sections: None
- Removed sections: None
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
* **Resource Bounds**: Active memory overhead for the local inference and execution engine MUST remain under 250MB RAM on standard commodity PC hardware.
* **Latency SLA**: Autocomplete shorthand resolution and LiveView socket DOM patches MUST achieve round-trip latencies under 15ms.
* **Cold-Boot Compilation SLA**: Cold-boot EXLA graph compilation, tensor allocations, and model weight loading MUST occur asynchronously during OTP supervision tree initialization prior to socket mount. The user interface MUST remain immediately and interactively responsive via Tier 1 (SQLite FTS5) while Tier 2 warms up in the background.

*Rationale*: Doctors prescribe under high-throughput patient loads on low-spec clinic computers; JIT compilation freezes during clinical consultation induce workflow abandonment and diagnostic interruptions.

### Article VII — Two-Tier Entity Resolution & Lexing Invariance
1. **Primary Tier**: Deterministic SQLite FTS5 trigram search against brand names.
2. **Fallback Tier**: Local vector similarity (via Nx + EmbeddingGemma 2 truncated to 256 dimensions using Matryoshka Representation Learning) ONLY when text search confidence falls below threshold.
3. **Presentation Filter**: Candidate vectors MUST always be constrained by clinical dosage form hints (`Tab`, `Syr`, `Cap`, `Inj`) to prevent cross-presentation formulation errors.
4. **Pharmacological Lexing Invariance**: Shorthand parsing MUST execute as a Deterministic Finite Automaton (DFA) or right-to-left token stream. Extraction of dosage matrices (`1+0+1`) and durations (`5d`) MUST NEVER consume, alter, or discard pharmaceutical strength indicators (`mg`, `ml`, `mcg`, `g`, `iu`, `%`, `mg/5ml`) belonging to the drug entity query.

*Rationale*: Balances blazing search speed with robust typo resilience. Strict token isolation prevents lethal numerical misattributions (e.g., mistaking strength `500mg` for duration `5d` or concentration `120mg/5ml` for a dosage schedule).

## Data Privacy & Cryptographic Immutability

### Article VIII — Encryption-at-Rest for Protected Health Information (PHI)
Patient identifying attributes (`name`, `contact`, `clinical_complaints`) MUST be encrypted at rest via Cloak / AES-GCM before writing to the local SQLite database. Public drug catalogs and reference formularies remain unencrypted for fast FTS5 index scanning.

*Rationale*: Enforces medical confidentiality and data protection in case clinical hardware is stolen or inspected by unauthorized personnel.

### Article IX — State Machine Invariance
* A prescription in `:draft` state permits mutations and modifications.
* A prescription transitioned to `:locked` is permanently immutable. No updates or deletions are permitted on a locked record under any circumstances.
* Prescriptions MUST NEVER be hard-deleted from disk; soft archival (`ash_archival`) and audit logging (`ash_paper_trail`) MUST be maintained for legal accountability.

*Rationale*: Medical records require tamper-evident immutability and complete forensic traceability under BM&DC guidelines.

### Article X — Offline Authenticity & Asymmetric Cryptographic Signing
Printed prescriptions MUST embed an offline-verifiable, detached Ed25519 cryptographic digital signature in a 2D QR code payload (`BMDC_NO || DATE || RX_ID || DRUG_IDS || ED25519_SIG`). The signature MUST be generated using the prescribing physician's offline local private key. Pharmacies and audit agents MUST be able to verify authentic authorship and payload integrity against the physician's public key recorded in the verified local BM&DC registry snapshot without internet access.

*Rationale*: Symmetrical hashes or plain SHA-256 checksums verify message integrity but cannot prove authenticity or prevent forgery; asymmetric Ed25519 signatures guarantee non-repudiation and prevent dispensary tampering while operating entirely offline.

## Behavior-Driven & Test-Driven Development (BDD / TDD)

### Strict Test-First Protocol (NON-NEGOTIABLE)
All clinical business logic, validation rules, interaction safety gates, and state machine transitions MUST strictly follow this non-negotiable sequence:

1. **Write Behavior Test First**: 
   Before any production code is drafted or altered, executable behavioral specifications MUST be written (`Phoenix.LiveViewTest`, `ExUnit`, Ash resource action tests). Tests must clearly express the clinical invariant or feature contract.
2. **Execute & Verify Red (Must Fail First)**:
   The test suite for the new specification MUST be executed against the codebase and explicitly observed to fail (Red). Writing implementation code prior to observing a failing test is a strict violation of this invariant. The test failure must specifically be due to the missing behavior or safety assertion, not due to syntax or compilation errors.
3. **Write Minimal Implementation (Green)**:
   Only once the test has failed as expected may production code be written—implementing only the minimal logic required to make the failing test pass.
4. **Refactor & Precommit Gate**:
   Refactor code for clarity and maintainability while keeping all tests passing. The full test suite and `mix precommit` must pass cleanly.
5. **Clinical Invariant Regression Gate**:
   Every Pull Request and commit must pass automated test suites asserting that Articles I through X cannot be bypassed:
   - Attempting to bypass the DGDA primary key foreign key relation in a prescription item fails unit tests.
   - Attempting to update or delete an item on a `:locked` prescription raises an immutable transition error.
   - Prescribing a Class-A narcotic via an unverified or telemedicine actor raises a forbidden validation error.
   - Cloak-encrypted fields are asserted to exist as binary ciphertexts on raw SQLite queries.
   - LiveView interaction benchmarks enforce rendering and resolution response limits.
   - Shorthand parser tests assert zero strength indicator corruption across edge-case token sequences.
   - Ed25519 signature verification fails on tampered QR code payloads.

## Governance & Agentic Fencing

1. **Constitutional Precedence**: This constitution supersedes all other architectural discussions, transient design choices, and code conventions in the `RxGenerator` project.
2. **Agentic Scope & Modification Fence**: Autonomous agents executing Spec Kit workflows (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, `/speckit.converge`) are **strictly prohibited** from:
   - Adding unauthorized Hex dependencies to `mix.exs`.
   - Modifying database adapters away from `AshSqlite` / SQLite3.
   - Introducing external cloud network drivers, cloud telemetry, or third-party web APIs.
   - Spawning external Python runtimes or heavy sidecar services to bypass Elixir/Nx/BEAM edge architecture.
   Any proposed exception requires an approved RFC under the Governance Amendment Procedure before execution.
3. **Amendment Procedure**: Amendments require formal RFC documentation, clinical safety justification, migration impact analysis, and explicit sign-off from clinical and technical stewards.
4. **Compliance Review**: All Pull Requests and automated builds must execute `mix precommit` and verification test suites to prove adherence to these constitutional invariants.

**Version**: 1.2.0 | **Ratified**: 2026-10-13 | **Last Amended**: 2026-10-13
