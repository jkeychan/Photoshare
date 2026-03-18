# Frontend Redesign — Appalachian Actors Photo Site

**Date:** 2026-03-17
**Status:** Approved for implementation

---

## Overview

Full frontend redesign of the Photoshare Flask app used by Appalachian Actors — a theatre company that produces one show per year with 2–3 performance days. The site is password-protected and used by members to browse and download event photos and videos.

Goals: modern clean aesthetic, fast keyboard and mouse navigation, theme system extensible by future developers, JS linting and minification pipeline, hardened CI.

---

## Disk / Data Structure

The media is organised on disk as follows (no changes to this structure):

```
/mnt/photoshare/media/
  Clue 2025/
    Day-1/           ← JPG photos
    Day-2/           ← JPG photos
    Video/           ← MP4/MOV files (may contain subfolders)
  Aladdin - Summer 2024/
    Day 1 (rained out)/
    Day 2/
    Day 3/
    Video/
  Princess Bride - Summer 2023/
    ...
  Beauty and the Beast - Summer 2022/
    ...
```

---

## Backend Changes (minimal)

The redesign is primarily frontend-only, but three small backend additions are required:

### 1. Remove pagination for gallery pages

`_PAGE_SIZE` in `app.py` (currently 10) is increased to a large number (e.g. 10000) so all photos in a day-folder load in a single request. The pagination UI is removed from the template. The existing pagination route parameters continue to work but are effectively a no-op. The existing guard `subdirs=subdirs if page == 1 else []` is harmless after this change since page will always be 1.

### 2. Show metadata for homepage cards

The index route is updated to pass a `shows` list of dicts instead of a bare `directories` list. Each dict contains:

```python
{
  "name": "Clue 2025",
  "path": "Clue 2025",
  "photo_count": 142,        # total .jpg/.jpeg/.png across all day-subfolders
  "thumb_url": None,         # reserved for future use; always None for now
}
```

Photo count is computed by a helper `_count_photos(show_path)` that walks one level of day-subfolders, explicitly excluding any subfolder named `video` (case-insensitive). It counts files with extensions `.jpg`, `.jpeg`, `.png`. The helper receives a path relative to `_MEDIA_ROOT` (the app's existing constant, derived from `_STATIC_ROOT / "media"`). Note: the disk layout diagram in this spec shows `/mnt/photoshare/media/` for readability, but the actual runtime path is whatever `_MEDIA_ROOT` resolves to — the helper must use `_MEDIA_ROOT`, never a hardcoded path.

### 3. Video subfolder detection on show page

The directory route always passes `has_video=True/False` in context. It is computed as: `any(d.lower() == 'video' for d in subdirs)`. The template only uses `has_video` when rendering the show-page view (i.e. when `subdirs` is non-empty). Show-level depth can be detected as `directory.count('/') == 0` if needed, but the template distinction already relies on `subdirs` being non-empty.

Videos shown are only the immediate `.mp4` and `.mov` files inside `Video/` — sub-subfolders (e.g. `Video/MOV-Format/`) are ignored. `.mov` files must use `type="video/quicktime"` in the `<source>` tag; `.mp4` files use `type="video/mp4"`.

The route also passes a new context variable `video_files`: a list of static URL strings for each video file inside `Video/`, computed when `has_video=True`. This is required because when the current directory is the show folder, `files` is empty — the template cannot otherwise list `Video/` contents. Example value: `["/static/media/Clue%202025/Video/clip1.mp4", ...]`.

---

## Pages

### 1. Login page (`/`)

Single password field, centred on screen. Styled to match the active theme. No username. CSRF-protected (existing behaviour preserved).

### 2. Homepage (`/` when logged in)

All shows displayed as cards in a responsive grid — never paginated (4 shows total, grows slowly). Cards are ordered newest-first. The most recent show gets a "Latest" badge.

Each card shows:
- Show name
- Year / season (parsed from folder name)
- Total photo count across all day-folders
- Solid colour placeholder thumbnail (no server-side image lookup needed)

Clicking a card navigates to the Show page.

### 3. Show page (`/directory/<show>/`)

Displays the contents of a single show folder.

**Performance day cards** (top section)
Each subfolder that is NOT named `Video` (case-insensitive) is shown as a large horizontal card. Card shows:
- Day name (e.g. "Day 1")
- Parenthetical note if present in the folder name (e.g. "(rained out)") shown as a muted subtitle
- Photo count for that day

**Videos section** (below day cards, only if `has_video=True`)
Immediate `.mp4` and `.mov` files inside `Video/` rendered as a grid of native `<video>` elements with controls. Sub-subfolders within `Video/` are not traversed. No lightbox — native player handles playback.

### 4. Gallery page (`/directory/<show>/<day>/`)

All photos displayed at once in a **justified-row layout** — each row is the same height, photos fill the full width respecting their natural aspect ratios. No pagination UI (pagination size set to 10000 server-side).

- Photo count shown at top ("142 photos")
- Clicking any photo opens the lightbox
- Keyboard: `←` / `→` to navigate photos, `Esc` to close, `D` to download current photo
- Download button visible in lightbox top-right corner

---

## Navigation

**Top bar** (all pages when logged in):

```
[Appalachian Actors]   [Home › Clue 2025 › Day 2]   [🎨] [Logout]
```

- Logo/name on left — always links to homepage
- Breadcrumb in centre — each segment is a clickable link
- Palette icon opens theme switcher dropdown (see Theme System)
- Logout on right

**Breadcrumb segments:**
- Homepage: no breadcrumb shown
- Show page: `Home › Clue 2025`
- Gallery: `Home › Clue 2025 › Day 2`

---

## Theme System

### Architecture

All colours and a small set of spacing/radius tokens are defined as CSS custom properties on `:root` in `static/css/themes.css`. A theme is an `html.theme-<name>` rule that overrides those variables. No other CSS changes per theme.

```css
/* themes.css — full structure */
:root {
  --bg-page: #f7f5f2;
  --bg-card: #ffffff;
  --bg-nav: #ffffff;
  --border: #e8e4df;
  --text-primary: #1a1a1a;
  --text-secondary: #888888;
  --accent: #1a1a1a;
  --accent-text: #ffffff;
  --shadow: rgba(0,0,0,0.08);
  --radius: 8px;
}

html.theme-noir   { --bg-page: #0a0a0a; --bg-card: #1a1a1a; /* ... */ }
html.theme-forest { --bg-page: #f2f5f0; --bg-card: #ffffff;  /* ... */ }
html.theme-slate  { --bg-page: #1e2533; --bg-card: #252d3d; /* ... */ }
/* Adding a new theme = one block here */
```

All selectors use `html.theme-*` (not `body.theme-*`) to match the FOUC-prevention script below.

### Built-in themes (4)

| Name | Page bg | Accent | Character |
|------|---------|--------|-----------|
| **Clean** (default) | `#f7f5f2` off-white | `#1a1a1a` charcoal | Neutral, professional |
| **Noir** | `#0a0a0a` black | `#c9a84c` gold | Dramatic, editorial |
| **Forest** | `#f2f5f0` sage | `#2d4a22` forest green | Earthy, outdoor |
| **Slate** | `#1e2533` navy | `#60a5fa` sky blue | Cool, contemporary |

### Theme persistence and FOUC prevention

Selected theme stored in `localStorage` under key `aa-theme`. Applied by a small `<script>` in `<head>` — before `<body>` renders — to prevent flash of unstyled content:

```html
<script>
  const t = localStorage.getItem('aa-theme');
  if (t) document.documentElement.classList.add('theme-' + t);
</script>
```

This adds the class to `<html>`, which is why all theme selectors use `html.theme-*`.

### Theme switcher UI

Palette icon in the nav bar opens a small dropdown showing 4 coloured swatches. Clicking one:
1. Removes all `theme-*` classes from `<html>`
2. Adds the new `html.theme-<name>` class
3. Saves the choice to `localStorage`

Active theme indicated with a ring/outline on its swatch. No page reload.

### Extensibility for future developers

Adding a new theme requires only:
1. One `html.theme-<name> { ... }` block in `themes.css`
2. One `<button>` swatch entry in the theme switcher in `base.html`

No Python changes, no build step, no config files.

---

## JavaScript

Two self-contained vanilla JS files (plain `<script>` tags, no bundler, no dependencies):

### `static/js/justified-rows.js`

Lays out `.gallery-grid` images into justified rows.

- Each `.gallery-thumb` has a `data-ratio` attribute (width/height as a float) set in the template from the image's filename or defaulting to `1.5`. This avoids waiting for image load to know dimensions.
- On `DOMContentLoaded`, calculates row breaks using `data-ratio` values to fill container width at a target row height (~220px desktop, ~160px mobile). Sets `width` and `height` on each item via inline styles immediately — no layout jump on image load.
- Re-runs on window `resize` (debounced 150ms).
- **Loading state**: images use `loading="lazy"` and display as grey placeholders (via CSS `background-color: var(--border)`) until loaded. Layout dimensions are set before load, so no reflow occurs when images arrive.

Note: Because aspect ratios are not known server-side without reading EXIF data (out of scope), `data-ratio` defaults to `1.5` for all images. Rows will be visually uniform width but not pixel-perfect to actual photo proportions. This is acceptable for the current use case.

### `static/js/lightbox.js`

- Opens on `.gallery-thumb` click
- Renders full-size image centred in a full-screen overlay (dark semi-transparent backdrop)
- Arrow buttons on left/right edges for mouse navigation
- Keyboard: `←` `→` navigate, `Esc` close, `D` download
- Download: creates a temporary `<a download href="...">` and programmatically clicks it
- Touch: swipe left/right gesture support
- Preloads the next image src for perceived speed

---

## JS Tooling

### Linting — ESLint

ESLint with a minimal flat config (`eslint.config.js`) targeting the two JS files. No plugins or framework-specific rules — just the standard recommended set for vanilla browser JS.

```js
// eslint.config.js
import js from "@eslint/js";
export default [
  js.configs.recommended,
  {
    files: ["static/js/**/*.js"],
    languageOptions: { ecmaVersion: 2022, sourceType: "script" },
    rules: {
      "no-unused-vars": "error",
      "no-undef": "error",
    },
  },
];
```

`sourceType: "script"` (not `"module"`) because the JS files are loaded as plain `<script>` tags, not ES modules.

ESLint is installed as a dev dependency via `package.json` in the repo root. It is not bundled or shipped — only used for linting in CI and locally.

### Minification — esbuild

esbuild minifies `static/js/justified-rows.js` and `static/js/lightbox.js` into `static/js/dist/`. It also minifies `static/css/styles.css` and `static/css/themes.css` into `static/css/dist/`.

```
static/js/dist/justified-rows.min.js
static/js/dist/lightbox.min.js
static/css/dist/styles.min.css
static/css/dist/themes.min.css
```

Templates reference the `dist/` paths in production. A `FLASK_ENV` or `DEBUG` flag controls which version is served:
- `DEBUG=True` (local dev): serve unminified originals — easier to read DevTools
- `DEBUG=False` (production): serve minified files from `dist/`

esbuild is also installed as a dev dependency. The build command is a single npm script:

```json
// package.json
{
  "scripts": {
    "lint": "eslint static/js/",
    "build": "esbuild static/js/justified-rows.js static/js/lightbox.js --minify --outdir=static/js/dist && esbuild static/css/styles.css static/css/themes.css --minify --outdir=static/css/dist"
  },
  "devDependencies": {
    "@eslint/js": "^9.0.0",
    "eslint": "^9.0.0",
    "esbuild": "^0.21.0"
  }
}
```

`static/js/dist/` and `static/css/dist/` are committed to git so the server never needs Node.js installed — the Docker image stays Python-only.

---

## CI Pipeline

### Current state

```
push → test (pytest) → deploy (self-hosted runner: git pull + docker compose up)
```

### Updated pipeline

```
push ──┬── lint-js  (ESLint)          ─┐
       ├── lint-py  (ruff + mypy)      ├── all pass → build → deploy → smoke-test
       └── test-py  (pytest)          ─┘
```

Four jobs run in parallel; `build` and `deploy` are sequential after all pass.

### Job: `lint-js`

Runs on `ubuntu-latest`. Steps:
1. Checkout
2. `npm ci`
3. `npm run lint`

Fails the build on any ESLint error. Runs on all pushes and PRs.

### Job: `lint-py`

Runs on `ubuntu-latest`. Steps:
1. Checkout
2. `pip install ruff mypy`
3. `ruff check app.py config.py`
4. `mypy app.py` (strict where possible; existing `# type: ignore` comments are acceptable)

### Job: `test-py`

Existing pytest job, unchanged except it now runs in parallel with the lint jobs rather than being the only pre-deploy gate.

### Job: `build`

Runs on `ubuntu-latest` after `lint-js`, `lint-py`, and `test-py` all pass. Steps:
1. Checkout
2. `npm ci`
3. `npm run build`
4. Commit the updated `static/js/dist/` and `static/css/dist/` files back to `main` using `git push`

**Only runs on `main`** (same condition as deploy). On feature branches, linting and tests run but no build commit is made.

The build commit uses a `[skip ci]` tag to prevent an infinite loop:
```
build: minify JS and CSS assets [skip ci]
```

**Permissions**: this job requires `contents: write` to push the commit. The workflow's global `permissions: {}` must be overridden at the job level:
```yaml
build:
  permissions:
    contents: write
```
All other jobs retain `contents: read` or no permissions, consistent with the existing workflow's least-privilege approach.

### Job: `deploy`

Runs on `self-hosted` after `build` completes. Unchanged from current:
```bash
cd ~/photoshare
git pull origin main
docker compose up --build -d --wait
```

### Job: `smoke-test`

Runs on `ubuntu-latest` after `deploy` completes. Verifies the site actually responds:

```bash
curl -sf --max-time 10 https://aa.photoshare.me/ -o /dev/null
```

A 200 or 302 (redirect to login) counts as success. Failure (connection refused, 5xx, timeout) fails the workflow and surfaces a real deployment problem that the current pipeline would silently miss.

### nginx config validation

Added as a step in `lint-py` (or its own job):
```bash
docker run --rm \
  -v ${{ github.workspace }}/nginx:/etc/nginx:ro \
  nginx:alpine nginx -t
```

Validates the nginx config against the actual nginx image used in production before any code reaches the server. Catches syntax errors in `nginx.conf`, `blockuseragents.rules`, and `blockpaths.rules` on every push.

---

## Files to Create / Modify

| File | Action | Notes |
|------|--------|-------|
| `app.py` | Modify | Increase `_PAGE_SIZE` to 10000; add `_count_photos()` helper; update index route to pass `shows` list; add `has_video` and `video_files` to directory route context; serve minified assets when `DEBUG=False` |
| `static/css/styles.css` | Rewrite | Layout, nav, cards, gallery grid, lightbox overlay, theme-aware component styles |
| `static/css/themes.css` | Create | CSS variable definitions for all 4 themes |
| `static/css/dist/styles.min.css` | Generated | Committed build artifact — do not edit manually |
| `static/css/dist/themes.min.css` | Generated | Committed build artifact — do not edit manually |
| `static/js/justified-rows.js` | Create | Justified-row gallery layout engine |
| `static/js/lightbox.js` | Create | Photo lightbox with keyboard/touch nav and download |
| `static/js/dist/justified-rows.min.js` | Generated | Committed build artifact — do not edit manually |
| `static/js/dist/lightbox.min.js` | Generated | Committed build artifact — do not edit manually |
| `templates/base.html` | Rewrite | New nav bar, breadcrumb, theme switcher dropdown, JS/CSS includes (minified in prod), FOUC script |
| `templates/index.html` | Rewrite | Show card grid |
| `templates/directory.html` | Rewrite | Show page (day cards + videos section) and gallery page (justified rows) |
| `templates/login.html` | Rewrite | Themed login form |
| `templates/error.html` | Update | Match new aesthetic |
| `templates/downloads.html` | Update | Match new aesthetic |
| `package.json` | Create | ESLint + esbuild dev dependencies and npm scripts |
| `eslint.config.js` | Create | Minimal flat ESLint config for vanilla browser JS |
| `.github/workflows/ci.yml` | Rewrite | Add lint-js, lint-py, build, smoke-test, nginx-validate jobs |

---

## Template Logic: Show page vs Gallery page

`directory.html` handles two distinct views depending on path depth. The template distinguishes them using context variables already passed by the route:

- **Show page** (`subdirs` is non-empty, or depth = 1): render day-card UI + videos section
- **Gallery page** (`subdirs` is empty, files are images): render justified-row photo grid

The `has_video` context variable (new) tells the show page whether to render the Videos section.

---

## Mobile

- Minimum supported width: 320px
- Homepage card grid: 2 columns ≥ 480px, 1 column below
- Gallery justified rows: target row height reduces to ~160px on mobile
- Lightbox: full screen, swipe to navigate, large tap targets for prev/next
- Nav: logo left, theme + logout right; breadcrumb wraps or truncates gracefully

---

## Out of Scope

- Sharing / social features
- User accounts or per-user permissions
- Search
- Upload interface
- PWA / offline support

---

## Success Criteria

- All shows visible on homepage with no pagination
- Photos in a gallery display in justified rows filling the viewport width
- Lightbox opens on click, responds to `←` `→` `Esc` `D` keyboard shortcuts
- Theme switcher in nav applies theme instantly with no page reload
- Adding a new theme requires only CSS + one HTML button — no Python
- Site works correctly at 320px minimum width
- `npm run lint` passes with zero errors on the two JS files
- `npm run build` produces minified assets; production serves minified versions
- CI lints JS, lints Python (ruff + mypy), runs tests, builds assets, deploys, and smoke-tests — all in one pipeline
- nginx config is validated in CI before every deploy
- A deployment failure causes the smoke-test job to fail visibly in GitHub Actions
