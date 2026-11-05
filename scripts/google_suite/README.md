# Google Forms + Sheets version of the navigator flow

**Parked.** The site is on the stand-in `demo/checkin.html` until the records
tool is decided. The Forms and spreadsheet under "What is built" are no longer
available, so these notes are a rebuild guide only.

Branch `google_suite_approach`. A fallback for showing the whole navigator
flow (architecture Option A, "Check-in") without REDCap. Demo data only: do not
collect real navigator names here until the IRB exempt determination and the
tool decision are settled.

## What you build in Google (about 30 minutes)

1. **Roster spreadsheet** (private). Extensions > Apps Script, paste
   `Code.gs`, run `setupRoster` (pass a count with `setupRoster(10)` from the
   editor, default 10). It makes the Roster and Dashboard tabs. Code
   N-000-0 is the test code.
2. **Consent Form** (stand-in): name, email, consent checkbox, typed
   signature. Copy the answers into the Roster by hand for the demo (or link
   it to its own sheet).
3. **Check-in Form**, four questions (two filled in by PEN, two feedback):
   - `Navigator code`: required, response validation > regular expression >
     matches `^N-[0-9]{3}-[0-9]$`
   - `Module`: required
   - `How useful did you find the content in this module?`: required, linear
     scale 1 (Not useful) to 5 (Very useful)
   - `Feedback or other thoughts on the content & accessibility of this module:`:
     optional, paragraph
   Keep these after `Module` so they land in columns D and E of `Check-ins`;
   the Dashboard reads only columns B and C. Do not insert or reorder columns
   in `Check-ins`. The `Feedback` tab (averages per module, open notes) reads
   from it by formula.

   Settings > Presentation > confirmation message:
   `Thank you. Your check-in is recorded.` then a link
   `https://ada-parc.github.io/PEN/?checkin=done` (use the local address when
   testing). Responses > Link to Sheets > the Roster spreadsheet, then rename
   the new tab to exactly `Check-ins`.
4. **Entry ids.** In the check-in Form: ⋮ > Get pre-filled link, type
   `N-000-0` and `module-01`, Get link, copy it. The link looks like
   `https://docs.google.com/forms/d/e/<FORM_ID>/viewform?usp=pp_url&entry.111=N-000-0&entry.222=module-01`.

## Feedback tab

After the two feedback questions are in the Form: Extensions > Apps Script in
the records spreadsheet, paste the updated `Code.gs`, run `setupFeedback`.

## Wire it to PEN

In `assets/checkin-init.html`, `SETTINGS`:

```js
form: "https://docs.google.com/forms/d/e/<FORM_ID>/viewform",
fields: { code: "entry.111", item: "entry.222", returnTo: "" },
```

Then render and test with `scripts/serve_site.py`, using
`?nav=N-000-0`.

## How it differs from the diagram

- Google Forms cannot redirect after Submit. The confirmation message holds a
  "Back to PEN" link, and PEN marks the check-in it opened as recorded. A
  navigator who clicks that link without submitting is marked recorded on
  their own screen only; the Dashboard still shows the truth.
- Pre-filled fields can be edited. The Dashboard counts a check-in only when
  the code and module match, and flags codes not on the Roster.

## Keeping names apart

The architecture keeps names in a private list and codes-only in Records. In
Google, make the check-in Form write to a second spreadsheet (no names) and
share that one with the wider team; keep the Roster private. The Dashboard
formulas then need an IMPORTRANGE for the Check-ins tab (change
`CHECKINS_SHEET` references accordingly).

## What is built (adaparcwebsite@gmail.com, 2026-11-02)

- Check-in Form "PEN navigator check-in (demo)", published, wired into
  `SETTINGS` in `assets/checkin-init.html` (entry ids 1572468452 for the code,
  110328935 for the module).
- Spreadsheet "PEN navigator records (demo)": tabs `Check-ins` (the Form's
  responses), `Roster` (codes N-000-0 to N-050-2, personal link formula), and
  `Dashboard` (built by hand with the same formulas as `Code.gs`, so the
  script is optional). Rows 2 to 52 carry formulas in both tabs. For more than
  50 navigators, fill the last row's formulas down and add codes from
  `scripts/navigator_codes.py`. Roster codes N-011-7 onward are one
  `TRANSPOSE(SPLIT(...))` formula in A13, so edit that formula rather than
  single cells.
- Tested end to end on a local site: link, pre-filled Form, submit,
  `?checkin=done` back to PEN, Dashboard tick. One N-000-0 / module-01 test row
  is in `Check-ins`; delete it before real use.
- Consent Form "PEN navigator consent (demo)", published: full name, email,
  consent checkbox, typed signature (all required). Responses go to a
  separate spreadsheet, "PEN consent responses (demo, names)", so names stay
  apart from the check-ins. One Test Navigator / test@example.com row is in it.
  Staff copy a consenting person's name and email into the Roster, next to the
  code they hand out.
- The confirmation link points at the live
  site (`ada-parc.github.io/PEN`), which only records once this branch is
  deployed. For a local demo, open `http://localhost:8000/?checkin=done`.

## Demo run-through (after this branch is deployed)

1. Open `https://ada-parc.github.io/PEN/?nav=N-000-0` (the test navigator).
   Use one browser for the whole run.
2. Open a module's check-in. The Google Form opens with the code and module
   already filled in. Submit it.
3. On the confirmation page, follow the link back to PEN. The check-in shows
   as recorded.
4. Open the `Dashboard` tab of the records spreadsheet. The N-000-0 row shows a
   tick for that module.

Before each demo, delete the N-000-0 rows from `Check-ins` and clear the site
data for `ada-parc.github.io` (or use a private window), so the run starts
clean. If the return link ever shows no navigator mode, the browser was
switched mid-run. The Sheet row is still correct.

Known limits: the return link is the same for everyone and relies on the same
browser, and the Form's "submit another response" link could not be switched
off.

## Look and feel (2026-11-02)

Both Forms use the PEN brick clay (#9B3A26) theme color, Georgia (Bitter is not
offered in Forms) at the largest sizes Forms allows, and plain-language
descriptions. The check-in Form's "submit another response" link is off. In the
records spreadsheet, `Dashboard` and `Roster` have a frozen navy header with
white bold text and wider columns, and the Dashboard's tick, count and
certificate columns are centered. Not done: highlight colors for ticks and
"Yes" (the conditional formatting panel did not fit the narrow browser pane).
