# RxGenerator

A clinical prescription generator built with Elixir, Phoenix LiveView, and the Ash Framework, featuring encrypted patient data at rest, offline-verifiable Ed25519 QR signatures, and print-ready prescription sheets.

---

## Documentation

- **[DESIGN.md](DESIGN.md)** — Architecture, Phoenix v1.8 / LiveView conventions, and Visual System & Clinical UI Invariants.
- **[ACCESSIBILITY.md](ACCESSIBILITY.md)** — Auditable WCAG 2.1 AA accessibility specification.
- **API & Module Docs** — Run `mix docs` to generate HTML (`doc/index.html`), Markdown (`doc/llms.txt`), and EPUB (`doc/rx_generator.epub`) documentation via `ExDoc`.

---

## Tech Stack

- **Elixir** `~> 1.17` / **Phoenix** `~> 1.8.15` / **Phoenix LiveView** `~> 1.2.0`
- **Ash Framework** `~> 3.0` (`ash_sqlite`, `ash_phoenix`, `ash_state_machine`, `ash_archival`, `ash_paper_trail`, `ash_cloak`, `cinder`)
- **Database**: SQLite (with FTS5 drug formulary search)
- **Styling**: Tailwind CSS v4
- **QR & Crypto**: `eqrcode`, Ed25519 signing & offline verification

---

## Getting Started

1. **Install dependencies, set up the database, and build assets:**
   ```bash
   mix setup
   ```
2. **Start the Phoenix server:**
   ```bash
   mix phx.server
   ```
   Or inside IEx:
   ```bash
   iex -S mix phx.server
   ```
3. Visit `http://localhost:4000` in your browser.

---

## Development & Verification

- **Run tests:**
  ```bash
  mix test
  ```
- **Run full pre-commit checks** (compile with `--warnings-as-errors`, unlock unused deps, format, and test):
  ```bash
  mix precommit
  ```
- **Generate ExDoc documentation:**
  ```bash
  mix docs
  ```

---

## Production Release

`mix.exs` includes a self-contained `rx_generator` release configuration (`include_erts: true`):

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```
