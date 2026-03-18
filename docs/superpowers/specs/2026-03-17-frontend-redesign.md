# Frontend Redesign — Appalachian Actors Photo Site

**Date:** 2026-03-17
**Status:** Approved for implementation

---

## Overview

Full frontend redesign of the Photoshare Flask app used by Appalachian Actors — a theatre company that produces one show per year with 2–3 performance days. The site is password-protected and used by members to browse and download event photos and videos.

Goals: modern clean aesthetic, fast keyboard and mouse navigation, theme system extensible by future developers.

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

Photo count is computed by a helper `_count_photos(show_path)` that walks one level of day-subfolders, explicitly excluding any subfolder named `video` (case-insensitive). It counts files with extensions `.jpg`, `.jpeg`, `.png`. The helper receives a path relative to `_MEDIA_ROOT` (the app's existing constant) — it must not hardcode `/mnt/photoshare/media/`.

### 3. Video subfolder detection on show page

The directory route always passes `has_video=True/False` in context. It is computed as: `any(d.lower() == 'video' for d in subdirs)`. The template only uses `has_video` when rendering the show-page view (i.e. when `subdirs` is non-empty). Show-level depth can be detected as `directory.count('/') == 0` if needed, but the template distinction already relies on `subdirs` being non-empty.

Videos shown are only the immediate `.mp4` and `.mov` files inside `Video/` — sub-subfolders (e.g. `Video/MOV-Format/`) are ignored. `.mov` files must use `type="video/quicktime"` in the `<source>` tag; `.mp4` files use `type="video/mp4"`.

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

## Files to Create / Modify

| File | Action | Notes |
|------|--------|-------|
| `app.py` | Modify | Increase `_PAGE_SIZE` to 10000; add `_count_photos()` helper; update index route to pass `shows` list; add `has_video` to directory route context |
| `static/css/styles.css` | Rewrite | Layout, nav, cards, gallery grid, lightbox overlay, theme-aware component styles |
| `static/css/themes.css` | Create | CSS variable definitions for all 4 themes |
| `static/js/justified-rows.js` | Create | Justified-row gallery layout engine |
| `static/js/lightbox.js` | Create | Photo lightbox with keyboard/touch nav and download |
| `templates/base.html` | Rewrite | New nav bar, breadcrumb, theme switcher dropdown, JS/CSS includes, FOUC script |
| `templates/index.html` | Rewrite | Show card grid |
| `templates/directory.html` | Rewrite | Show page (day cards + videos section) and gallery page (justified rows) |
| `templates/login.html` | Rewrite | Themed login form |
| `templates/error.html` | Update | Match new aesthetic |
| `templates/downloads.html` | Update | Match new aesthetic |

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
