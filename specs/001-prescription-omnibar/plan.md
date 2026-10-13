# Implementation Plan: Keyboard-Driven Prescription Omnibar

**Branch**: `001-prescription-omnibar` | **Date**: 2026-10-13 | **Spec**: [spec.md](file:///d:/Rx_generator/specs/001-prescription-omnibar/spec.md)

**Input**: Feature specification from `specs/001-prescription-omnibar/spec.md`

## Summary

Build a single-line, keyboard-driven Phoenix LiveView prescription omnibar. Clinical shorthand (`napa xtra 1+0+1 5d pc`) is tokenized via a deterministic finite automaton (DFA) parser, resolving drug products against the local DGDA SQLite catalog via SQLite FTS5 trigram indexes under 5ms. The prescription canvas renders the active generic molecule in bold, prominent uppercase typography (`String.upcase(generic_name)`) adhering to High Court directives, alongside canonical colloquial Bengali directions (`১+০+১ — ভরা পেটে — ৫ দিন`).

## Technical Context

**Language/Version**: Elixir 1.20.4, Erlang/OTP 29
**Primary Dependencies**: Ash Framework 3.0, AshPhoenix 2.0, AshSqlite 0.2, Phoenix LiveView 1.2, Tailwind CSS (v4 pure CSS import format in `app.css`), Cinder 0.17
**Storage**: SQLite3 with SQLite FTS5 virtual tables (`ecto_sqlite3` / `ash_sqlite`)
**Testing**: ExUnit, `Phoenix.LiveViewTest`, `LazyHTML`
**Target Platform**: Edge local PC / air-gapped clinic hardware (Windows / Linux)
**Project Type**: Phoenix LiveView Web Application
**Performance Goals**: FTS5 candidate filtering <2ms, LiveView socket round-trip DOM patch <15ms
**Constraints**: Fully air-gapped (zero cloud network calls), zero npm runtime dependencies, memory overhead <250MB
**Scale/Scope**: Outpatient clinical consultation, ~30,000 DGDA drug SKUs locally indexed

## Constitution Check (Scoped to Spec 01)

- **Article I (Zero Hallucination)**: PASS. Resolves strictly against local DGDA SQLite snapshot primary keys. No generative models generate pharmacology.
- **Article II (High Court Generic Mandate)**: PASS. Canvas renders `String.upcase(generic_name)` with equal/greater prominence than commercial brands.
- **Article III (HITL Absolute)**: PASS. Physician explicitly controls and confirms all additions via keyboard (`Enter`).
- **Article IV (Controlled Substances)**: PASS. Narcotic flag check embedded in Ash validation pipeline.
- **Article V (Zero-Cloud Edge Autonomy)**: PASS. All regex/DFA lexing, FTS5 matching, and translations run 100% locally.
- **Article VI (Memory & Latency SLA)**: PASS. FTS5 queries benchmarked <2ms; socket DOM patches <15ms.
- **Article VII (Lexing & Strength Invariance)**: PASS. Right-to-left DFA lexer isolates dose/duration while protecting strength indicators (`mg`, `ml`, `mcg`).
- **Article VIII (Encryption-at-Rest)**: DEFERRED TO SPEC 02 (Draft canvas operates in-memory; persistent PHI encryption activated in persistence/profile spec).
- **Article IX (State Machine Invariance)**: SCOPED. Spec 01 implements active draft staging; final immutable locking (`:locked`) deferred to Print Spec.
- **Article X (Ed25519 Offline Signing)**: DEFERRED TO SPEC 03 (QR code and PDF signature generation deferred to Print Spec).
- **Agentic Modification Fence**: PASS. Strictly adheres to Ash, AshSqlite, and Phoenix dependencies without new Hex packages or DB adapter swaps.

## Project Structure

### Documentation (this feature)

```text
specs/001-prescription-omnibar/
├── plan.md              # This file
├── research.md          # Architectural research & decisions
├── data-model.md        # Ash domains, resources, and structs
├── quickstart.md        # Verification scenarios and test execution guide
├── contracts/           # LiveView socket event protocols & component contracts
│   └── omnibar_contracts.md
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code Architecture

```text
lib/
├── rx_generator/
│   ├── formulary/
│   │   ├── drug_catalog_item.ex     # Ash resource for DGDA snapshot
│   │   └── search.ex                # Raw SQLite FTS5 trigram queries via Ecto
│   ├── prescriptions/
│   │   ├── prescription.ex          # Ash resource (draft state)
│   │   ├── prescription_item.ex     # Ash resource for canvas line items
│   │   ├── shorthand_parser.ex      # DFA token stream lexer
│   │   ├── parsed_shorthand.ex      # Token struct
│   │   └── bengali_translator.ex    # Canonical Bengali directions formatter
│   └── repo.ex                      # Ecto Repo for SQLite
├── rx_generator_web/
│   ├── components/
│   │   ├── core_components.ex       # Headless omnibar & canvas UI
│   │   └── layouts/
│   ├── live/
│   │   └── prescription_live.ex     # Omnibar keyboard LiveView
│   └── router.ex
test/
├── support/
│   ├── formulary_fixtures.ex        # In-memory / seeded 10-drug test catalog
│   ├── conn_case.ex
│   └── data_case.ex
├── rx_generator/
│   ├── formulary/
│   │   └── search_test.exs
│   └── prescriptions/
│       ├── shorthand_parser_test.exs
│       ├── bengali_translator_test.exs
│       └── prescription_test.exs
└── rx_generator_web/
    └── live/
        └── prescription_live_test.exs
```

## Phase 0 & Phase 1 Outputs Complete

- **Phase 0 (Research)**: Documented in [`research.md`](file:///d:/Rx_generator/specs/001-prescription-omnibar/research.md)
- **Phase 1 (Design & Contracts)**:
  - Data models documented in [`data-model.md`](file:///d:/Rx_generator/specs/001-prescription-omnibar/data-model.md)
  - UI & socket event contracts in [`contracts/omnibar_contracts.md`](file:///d:/Rx_generator/specs/001-prescription-omnibar/contracts/omnibar_contracts.md)
  - Quickstart test guide in [`quickstart.md`](file:///d:/Rx_generator/specs/001-prescription-omnibar/quickstart.md)
