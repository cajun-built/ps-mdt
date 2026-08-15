# Design QA — Command Dashboard

## Reference

- Source: `exec-690be4f5-aa8b-4c4c-8097-de32afbecfcf.png`
- Target viewport: 1933 × 813
- Implementation capture: `design-qa-implementation-final.png` (local QA artifact; not shipped)

## Visual comparison

- [x] Full-screen, opaque dark terminal shell matches the selected command-desk direction.
- [x] Department crest, department name, officer identity, duty state, and grouped navigation occupy the left rail.
- [x] Dashboard hierarchy matches the reference: shift header, four KPIs, priority lists, unit status, recent reports, hearings, and open cases.
- [x] Accent colors and status colors remain restrained and readable against the dark surfaces.
- [x] Dense 1933 × 813 layout fits without horizontal overflow.
- [x] Department logo failure state renders a deliberate icon fallback.

## Functional QA

- [x] Production frontend build completes.
- [x] Sidebar navigation opens the existing MDT pages and returns to Dashboard.
- [x] Callsign control opens and closes its modal.
- [x] Existing live dashboard service remains the source of warrants, BOLOs, reports, bulletins, hearings, cases, units, and impound totals.
- [x] Browser-only preview data is isolated from the FiveM runtime.
- [x] No new browser console errors were introduced.

## Findings resolved

- P1: Removed the inset/translucent outer frame so the UI no longer exposes the game world through the terminal.
- P1: Removed duplicate utility and instance bars from the Dashboard route to match the selected hierarchy.
- P1: Corrected the main grid ratio and vertical rhythm to match the reference composition.
- P2: Added realistic preview data and unit-status states so all dashboard regions can be visually inspected.
- P2: Tightened the navigation so every section remains reachable at the target viewport.

Final result: passed.
