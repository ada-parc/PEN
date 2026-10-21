<img src="assets/brand/pen-badge.svg" width="64" height="64" alt="" />

# ADA-PARC-PEN

**PEN**, Participation Equity Navigator, is the
training companion to the [ADA-PARC](https://adaparc.shinyapps.io/ADA_PARC/)
project. It is a small, self-paced course that teaches disability advocates how
to read and use the data on the ADA-PARC website.

This repository is the **source for the PEN website**. It builds to a static
HTML site. There is no server, no database, and no login. Progress tracking is
done entirely in the trainee's own browser.

---

## How it is built

| Piece | Choice | Why |
| --- | --- | --- |
| Site generator | [Quarto](https://quarto.org) website, static HTML | A successor who does not write R can still fix a typo, swap a video, or add a module. |
| Progress tracking | `localStorage` in the browser, no accounts | See `assets/progress-init.html`. |
| Module + unit pages | Generated from one YAML file + two templates | Every page follows the same shape and cannot drift apart. |
| Styling | `assets/tokens.css` + `assets/pen.scss` on Quarto's Bootstrap theme | PEN's own design system: Bitter typeface at a 19px root; navy, cream, and brick clay palette; WCAG 2.2 AA measured, not assumed. |
| Hosting | GitHub Pages, published by GitHub Actions | Free, organization-owned, nothing to transfer at handoff. The public site carries no GitHub branding or links. |

## Site map

| Navbar | Page | Notes |
| --- | --- | --- |
| Home | `index.qmd` | Hero with the PEN brand line and the "Your progress" panel (Modules 1 to 3, with live progress). Module 4 is reached from the navbar. |
| Modules | menu | Modules 1 to 4. |
| Resources | `modules/module-04.qmd` | Module 4. Same page as the menu's 04 entry. |
| Certificate | `certificate.qmd` | Unlocks once every unit in Modules 1 to 3 is complete. Also reached from a banner on the home page and Module 3. |
| How to Use | `how-to-use.qmd` | Orientation, how progress is stored, reset control. |
| Help | `help.qmd` | FAQ, report a problem, glossary link (opens in a new tab). |
| An initiative of ADA-PARC ↗ | external | Opens the ADA-PARC app in a new tab. |

`accessibility.qmd` is linked from the footer and from Help, not the navbar. The
navbar collapses to a menu button below 1200px.

## Repository layout

```
_quarto.yml                 site config, navbar, footer, theme, pre-render hook
index.qmd                   home page: hero, brand line, "Your progress" panel
how-to-use.qmd              orientation, progress, reset control
certificate.qmd             certificate of completion (unlocks once Modules 1 to 3 are done)
help.qmd                    FAQ, report a problem, glossary link (opens in a new tab)
accessibility.qmd           accessibility statement + report a barrier

content/modules.yml          THE CONTENT SPINE for Modules 1 to 3. Edit this.
modules/_module-template.qmd    module landing page template
modules/_unit-template.qmd      unit page template
modules/module-0N.qmd           GENERATED (gitignored), module landing page
modules/module-0N-unit-YY.qmd   GENERATED (gitignored), one page per unit
modules/module-04.qmd           HAND-AUTHORED, Module 4 "Resources"; no units, not progress-tracked

assets/tokens.css           PEN design tokens: the eight colors, the role tokens, type scale, and the dark and
                            high-contrast themes
assets/pen.scss             site theme; every color is a role token, never a brand name
assets/display-init.html    Display settings, part 1: applies saved choices in <head> before first paint
assets/display-settings.html  Display settings, part 2: the fixed button and panel on every page
assets/progress-init.html   progress tracking + certificate gate, inlined on every page
assets/pen-manifest.html    GENERATED (gitignored), module -> unit id map (inline script)
assets/navbar-brand.html    navbar brand accessibility fixes
assets/icons.html           PNG favicon + apple-touch-icon links
assets/brand/               PEN and ADA-PARC marks (svg; png/ holds favicon PNGs)
assets/downloads/glossary.html  HAND-AUTHORED standalone glossary page, not a Quarto document
assets/downloads/glossary.pdf   GENERATED from glossary.html by R/build_glossary_pdf.R; the Help page's download

R/build_modules.R           generates modules/*.qmd + assets/pen-manifest.html from modules.yml
R/build_glossary_pdf.R      regenerates glossary.pdf (needs local Chrome; run by hand)
R/check_contrast.R          asserts the contrast floor for every role pair in all three themes
R/post_render.R             post-render hook: removes the unused _site/search.json Quarto writes anyway

scripts/style_snapshot.mjs  regression tools over the built site, driving headless Chrome: snap/diff (computed
                            styles and geometry), scan (rendered contrast, all states), overflow (every
                            theme, text size, font and width). Needs Node 22+, local Chrome, _site/ served.
scripts/serve_site.py       serve _site/ with Range support (video testing)
scripts/prepare_captions.py raw caption exports in videos/ -> assets/captions/*.vtt + transcripts/*.txt

assets/captions/            cleaned WebVTT captions
transcripts/                on-page transcript text
videos/                     unit videos (.mp4); raw caption exports here stay local

.github/workflows/publish.yml   render + deploy on push to main
```

## Build it locally

Prerequisites: [Quarto](https://quarto.org/docs/get-started/) 1.4.537 (the
version CI uses) and R with the `yaml` package (`install.packages('yaml')`).

On a fresh clone, generate the module and unit pages once, then build:

```bash
Rscript R/build_modules.R
```

```bash
quarto preview
```

`quarto render` builds once into `_site/`. Both run `R/build_modules.R` first
(the `pre-render` hook in `_quarto.yml`), so the module and unit pages and the
progress manifest are always regenerated from `content/modules.yml`. Quarto
decides which pages to render before that hook runs, which is why a fresh clone
needs the one manual run above.

To play videos locally, render, then serve with range support
(`python3 scripts/serve_site.py`, see the header of that file). `quarto preview`
cannot seek.

## Common tasks

### Edit a module or unit (Modules 1 to 3)

1. Open `content/modules.yml` and edit the module block (title, summary,
   objectives, `adaparc_pages` links, downloads) or one of its `units` entries (title, video, slides).
2. `quarto preview`. The module and unit pages regenerate.

Never edit `modules/module-01.qmd`, `module-02.qmd`, `module-03.qmd`, or any
`module-XX-unit-YY.qmd` by hand; they are overwritten on every build.
`modules/module-04.qmd` (Resources) is the one page in that folder meant to be
hand-edited. It is not in `modules.yml` and the build script never touches it.

### Add a unit's video, captions, and slides

Put the `.mp4` under `videos/<module>/` and the slide deck under
`assets/downloads/<module>/`, then point the unit at them in
`content/modules.yml`. The field list is in the comment at the top of that file.

```yaml
  units:
    - id: "01"
      title: "ADA History"
      video: videos/module_1/History_of_ADA.mp4
      duration: "9:54"                  # m:ss, required with `video`
      slides: assets/downloads/module_1/01-ADA-History.pptx   # optional
```

A unit recorded as several videos uses a `videos:` list instead (see Module 2).
For captions and a transcript, add the raw export to `VIDEOS` in
`scripts/prepare_captions.py` and run `python3 -I scripts/prepare_captions.py`.
A module whose units have no decks sets `no_slides: true`. Strip author names
and edit history from any `.pptx` before adding it (File > Inspect Document in
PowerPoint).

### Add a module or unit

Add a block to `content/modules.yml` (a new module needs `id`, `title`,
`summary`, etc.; a new unit inside an existing module needs `id`,
`title`, and its `video` or `videos`). For a new tracked module, also add it to the home page
Module Tracker (`index.qmd`) and the navbar `Modules` menu in `_quarto.yml`.
Then build. Page generation and the progress manifest pick it up
automatically. Module 4 is not part of this pipeline; edit
`modules/module-04.qmd` directly.

### Edit the glossary

Edit `assets/downloads/glossary.html`, then regenerate the PDF the Help page
serves, then build:

```bash
Rscript R/build_glossary_pdf.R
```

Keep each entry's `#term-*` anchor, and keep every term a module uses in the
glossary.

### Change a color or type size

`assets/tokens.css` holds PEN's tokens. Components in `assets/pen.scss` read
**role** tokens (`--pen-ink`, `--pen-surface`, `--pen-accent`, and so on),
never a brand name, so a theme is a block of values in `tokens.css`. To retune a
theme, change its values there, then run `Rscript R/check_contrast.R`. The SCSS
variables at the top of `pen.scss` exist only so Bootstrap can compile. There is
no automated check that they agree with `tokens.css`.

### Display settings (theme, text size, and so on)

The "Display" button and panel are built by `assets/display-settings.html`; the
saved choices are applied before first paint by `assets/display-init.html`. Both
are listed in `_quarto.yml`. Choices live in one localStorage key,
`pen:display:v1`, and never leave the browser. To test the site against the
regression tools, serve `_site/` (`python3 -m http.server 8123 -d _site`), then:

```
node scripts/style_snapshot.mjs scan --theme=dark            # rendered contrast, all states
node scripts/style_snapshot.mjs scan --theme=contrast --aaa=1
node scripts/style_snapshot.mjs overflow                     # every theme, size, font, width
node scripts/style_snapshot.mjs snap before.json             # then make a change, snap again,
node scripts/style_snapshot.mjs diff before.json after.json  # and diff: only intended changes
```

## How it publishes

Push to `main` → `.github/workflows/publish.yml` generates the module pages,
renders the site, and deploys it to GitHub Pages. Enable Pages once, in the
repository settings, with source **GitHub Actions**. This is a build/hosting
mechanism only. Nothing on the rendered site links back to GitHub.

The site URL is set in `_quarto.yml` (`site-url`, currently a placeholder).

## Accessibility

Target is **WCAG 2.2 AA** across the site, enforced rather than aspired to:
contrast, axe, heading outline, a 16px text floor, keyboard, 400% zoom and
320px reflow, greyscale, and screen reader. Contrast (all three themes,
including hover and focus), heading outline, font floor, and reflow (including
at larger text sizes) have been measured on the rendered site. An axe-core 4.10
run (WCAG 2.0 to 2.2 A/AA plus best practices, 2026-10-19, 14 representative
pages in the default theme) found no violations beyond one moderate
best-practice item: two unlabeled `nav` landmarks on pages that have both the
navbar and an "On this page" menu. A full VoiceOver/NVDA pass and testing with
real PEN trainees have **not been done yet**. The public statement is
`accessibility.qmd`; keep it true to what is measured.

## License

See [`LICENSE`](LICENSE). Proposed: CC BY 4.0 (content), MIT (code), pending
confirmation.
