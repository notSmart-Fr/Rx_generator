# Implementation Plan: Keyboard-Driven Prescription Omnibar

**Branch**: `001-prescription-omnibar` | **Date**: 2026-10-13 | **Spec**: [spec.md](file:///d:/Rx_generator/specs/001-prescription-omnibar/spec.md)

**Input**: Feature specification from `specs/001-prescription-omnibar/spec.md`

## Summary

Build a single-line, keyboard-driven Phoenix LiveView prescription omnibar. Clinical shorthand (`napa xtra 1+0+1 5d pc`) is tokenized via a deterministic finite automaton (DFA) parser, resolving drug products against the local DGDA SQLite catalog via SQLite FTS5 trigram indexes under 5ms. The prescription canvas renders the active generic molecule in bold, prominent uppercase typography (`String.upcase(generic_name)`) adhering to High Court directives, alongside canonical colloquial Bengali directions (`১+০+১ — ভরা পেটে — ৫ দিন`).

## Technical Context

**Language/Version**: Elixir 1.20.4, Erlang/OTP 29
**Primary Dependencies**: Ash Framework 3.0, AshPhoenix 2.0, AshSqlite 0.2, AshStateMachine 0.2, Phoenix LiveView 1.2, Tailwind CSS (v4 import format), Cinder 0.17
**Storage**: SQLite3 with SQLite FTS5 (`ecto_sqlite3` / `ash_sqlite`)
**Testing**: ExUnit, `Phoenix.LiveViewTest`, `LazyHTML`
**Target Platform**: Edge local PC / air-gapped clinic hardware (Windows / Linux)
**Project Type**: Phoenix LiveView Web Application
**Performance Goals**: FTS5 candidate filtering <2ms, LiveView socket round-trip DOM patch <15ms
**Constraints**: Fully air-gapped (zero cloud network calls), zero npm runtime dependencies, memory overhead <250MB
**Scale/Scope**: Outpatient clinical consultation, ~30,000 DGDA drug SKUs locally indexed

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Article I (Zero Hallucination)**: PASS. All drug entries resolve deterministically to exact primary keys in local DGDA SQLite snapshot. No generative models generate pharmacology.
- **Article II (High Court Generic Mandate)**: PASS. Canvas renders active generic in uppercase typography (`String.upcase/1`) with equal/greater prominence than commercial brands.
- **Article III (HITL Absolute)**: PASS. Physician explicitly controls and confirms all additions.
- **Article IV (Controlled Substances)**: PASS. Narcotics Flag on catalog enforces validation guard.
- **Article V (Zero-Cloud Edge Autonomy)**: PASS. All parsing, FTS5 searching, and translation run 100% locally.
- **Article VI (Memory & Latency SLA)**: PASS. Pure Elixir token lexer + SQLite FTS5 yields <5ms query time and well under 250MB RAM.
- **Article VII (Lexing & Strength Invariance)**: PASS. Right-to-left DFA lexer protects strength numbers (`mg`, `ml`, `mcg`) from being stripped as duration/frequency.
- **Article VIII (Encryption-at-Rest)**: PASS. PHI fields encrypted via Cloak AES-GCM; public catalog left unencrypted for FTS5 scanning.
- **Article IX (State Machine Invariance)**: PASS. Prescriptions managed via `AshStateMachine` (`:draft` to `:locked`), soft deletion via `AshArchival`.
- **Article X (Ed25519 Offline Signing)**: PASS. Detached digital signatures generated for offline QR code verification.
- **Agentic Modification Fence**: PASS. Zero new unauthorized Hex packages or database adapter changes.

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
│   │   └── search.ex                # SQLite FTS5 trigram queries
│   ├── prescriptions/
│   │   ├── prescription.ex          # Ash resource with AshStateMachine
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
