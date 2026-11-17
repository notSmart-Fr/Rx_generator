# Quickstart & Verification Guide: Two-Column Clinical Workspace & Real-Time A4 Paper Preview

**Feature**: `007-split-stage-omnibar-preview`  
**Date**: 2026-11-17  

---

## Prerequisites

1. Elixir ~> 1.17, Erlang/OTP 27+
2. Dependencies installed and SQLite seeded: `mix setup`

---

## 1. Automated Verification Commands

### Run BengaliTranslator Unit & Property Tests
```powershell
mix test test/rx_generator/prescriptions/bengali_translator_test.exs test/rx_generator/prescriptions/bengali_translator_property_test.exs
```
**Expected Outcome**:
- `:ac` / `"ac"` translates to `"খাবার ৩০ মিনিট আগে"`.
- `:empty` / `"empty"` translates to `"খালি পেটে"`.
- `"continue"` / `"cont"` translates to `"চলবে"`.
- Morning/noon/night slot breakdown (`সকাল ১, দুপুর ০, রাত ১`) renders for matrix doses and returns `nil` for `"SOS"` / `"as_directed"`.

### Run PrescriptionLive Two-Column & Omnibar Tests
```powershell
mix test test/rx_generator_web/live/prescription_live_test.exs
```
**Expected Outcome**:
- Selecting a candidate row from `#omnibar-dropdown` via mouse click adds the medication card directly to the right `Rx` column.
- One-tap Dose, Timing, Duration, and free-text Note updates patch both the Rx card and live A4 paper preview.
- Clicking `C/C`, `O/E`, `Dx`, `Ix` prefix helpers populates the 1/3 left clinical notes box, and leaving it empty keeps the A4 preview left margin blank.
- Clicking Bengali advice chips populates the General Advice footer.
- Patient clinical notes and general advice remain encrypted at rest in SQLite via `AshCloak`.

### Run Full Precommit Gate
```powershell
mix precommit
```

---

## 2. Manual Visual Verification (Greyscale Wireframe & Live A4 Preview)

1. Start server: `mix phx.server`
2. Open `http://localhost:4000/prescriptions/new`
3. Verify the side-by-side layout: drafting controls on the left, live A4 paper preview (with chamber header, patient strip, 1/3 + 2/3 two-column body, advice footer, and QR seal placeholder) on the right.
4. Search `"nap"` in the omnibar and click `"Napa"` with the mouse -> verify it immediately adds a card in the `Rx` column without input blur swallowing the click.
5. Click `30 mins before meal` (`খাবার ৩০ মিনিট আগে`) and `Continue` (`চলবে`) on the card -> verify real-time update on the A4 preview including morning/noon/night breakdown subtext.
