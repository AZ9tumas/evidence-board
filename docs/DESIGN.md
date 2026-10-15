# Evidence Board — macOS App Design Document

> A free-form, infinite canvas for collecting **text**, **images** and **webpages**, pinning them up, and connecting the dots with red string.
> Native macOS · SwiftUI + AppKit + Core Animation · Xcode project · boards saved as plain JSON.

| | |
|---|---|
| **Status** | Draft v1.0 — design spec, pre-implementation |
| **Platform** | macOS 15 Sequoia and later (Liquid Glass materials on macOS 26 Tahoe and later) |
| **Language** | Swift 6 (strict concurrency) |
| **UI** | SwiftUI for the app chrome and cards, AppKit + Core Animation for the canvas engine |
| **File format** | `.evboard`: UTF‑8 JSON that conforms to `public.json` (plain `.json` files open too) |

---

## Table of contents

1. [Vision](#1-vision)
2. [Product principles](#2-product-principles)
3. [Core concepts](#3-core-concepts)
4. [Feature specification](#4-feature-specification)
5. [Interaction design](#5-interaction-design)
6. [Visual design system](#6-visual-design-system)
7. [Rich link previews](#7-rich-link-previews)
8. [File format (JSON)](#8-file-format-json)
9. [Architecture](#9-architecture)
10. [Canvas rendering engine](#10-canvas-rendering-engine)
11. [Performance budgets](#11-performance-budgets)
12. [Xcode project setup](#12-xcode-project-setup)
13. [Security & privacy](#13-security--privacy)
14. [Accessibility](#14-accessibility)
15. [Testing strategy](#15-testing-strategy)
16. [Roadmap](#16-roadmap)
17. [Appendix: keyboard shortcuts](#appendix-a-keyboard-shortcuts)

---

## 1. Vision

The detective's corkboard, rebuilt as a modern Mac app. You drop in a quote, a screenshot or a link. Each one becomes a card on an infinite board. You drag cards around freely and run string between them until the picture comes together.

Three goals:

1. **Free.** There's no grid, no columns and no hierarchy. Cards go wherever you put them.
2. **Beautiful.** Every surface is designed: deep gradients, glass, layered soft shadows and link cards that look like editorial covers.
3. **Fast and portable.** It stays at 120 fps on large boards, and a board is one JSON file you can save, share, version in git and load anywhere.

### What it is *not*

- Not a whiteboard. There are no freehand drawing, shapes or sticky-note clutter tools.
- Not a notes app. There are no folders, tags database or rich-text documents.
- Not a browser. Webpages show as **preview cards**, not live embedded sites. A live view is an on-demand peek (§7.7).

---

## 2. Product principles

| Principle | What it means in practice |
|---|---|
| **Three things only** | A card is **Text**, **Image** or **Web**. Nothing else can be placed on the board. Strings connect cards, and they aren't cards themselves. |
| **The board is the document** | One file holds everything, images and link snapshots included. A board opened offline, years later, looks exactly as you saved it. |
| **Direct manipulation** | Everything is drag, drop, paste or double-click. Inspectors are optional. |
| **Quality over quantity** | Few features, each polished to the last pixel and the last millisecond. |
| **Zero idle cost** | When you're not touching the app, it uses 0% CPU and no network. |

---

## 3. Core concepts

```
Board ─┬─ Cards (nodes)
       │    ├─ TextCard   — a note, headline or typewriter snippet
       │    ├─ ImageCard  — a photo or screenshot, optionally captioned
       │    └─ WebCard    — a URL rendered as a rich, gradient link preview
       ├─ Strings (connections) — card ↔ card, optionally labelled
       ├─ Assets — deduplicated binary blobs (images, link thumbnails, favicons)
       └─ Viewport — the last camera position and zoom
```

- **Card**: a positioned, sized and slightly rotatable rectangle in *world space*.
- **Pin**: the push-pin at the top of each card. Strings attach to pins. That's the visual "connect the dots" anchor.
- **String**: a curved line between two pins that sags like real thread. It can have a color, a label and an arrow direction.
- **World space**: an unbounded 2D plane (Double precision) with origin `(0, 0)`. The camera maps world space to the screen.

---

## 4. Feature specification

### 4.1 Board (canvas)

- Infinite in every direction, with zoom from **5% to 800%**.
- The background is a themed gradient plus an optional subtle texture (dot grid, cork grain or blueprint lines), drawn procedurally so it never pixelates.
- A **minimap** sits in the bottom-right corner. It fades in while you pan or zoom and fades out after 1.5 s idle (it stays while the pointer is over it, and `View ▸ Always Show Minimap` keeps it up). It shows every card as a small tile in its tint and every string as a hairline; click or drag in it to move the view there.
- A **zoom HUD** sits in the bottom-left corner: `−  72%  +`, with a click to choose presets (Fit, 50%, 100%, 200%).

### 4.2 Text card

- Plain text with a **style** preset. The data stays plain text, and the style only changes how it looks:
  - **Note**: SF Pro Text 15, comfortable leading. The default.
  - **Headline**: SF Pro Display Bold 28. Use it for case titles and section labels.
  - **Typewriter**: SF Mono 14 on a paper-tinted card. Use it for quotes and transcripts.
- Inline editing on double-click. Markdown-lite rendering for `**bold**`, `*italic*` and `` `code` `` through `AttributedString(markdown:)`. The source stays plain text in JSON.
- Auto-height. You can resize the width, and the height follows the content until you resize it by hand.
- Tint: one of 8 theme accent colors, applied as a soft top gradient band.

### 4.3 Image card

- Sources: drag from Finder or a browser, paste (⌘V), or the `Insert ▸ Image…` panel.
- Supported: PNG, JPEG, HEIC, GIF (first frame), WebP, TIFF and PDF (first page).
- Optional **caption** (single line, under the image, in the polaroid style).
- **Frame styles**: *Polaroid* (white border with a thick bottom), *Borderless* (rounded 10 pt corners) and *Photo* (thin border with a deckled shadow).
- **Reframe** (non-destructive crop): double-click the photo, then drag to pan it inside its frame and scroll or pinch to zoom it, with the rest of the image shown faded around the card. ↩ or a click elsewhere keeps it, Esc puts it back. The crop is stored as a normalized rect; the photo area always shows it "aspect filled", so resizing the card never distorts the photo.
- Double-click the caption area (or press ↩) to edit the caption in place.
- Photos resize with their shape kept; hold ⇧ to change the shape.
- On import, images over **4096 px** on the long edge are downsampled. PNG and upright JPEG files that fit are stored byte for byte; HEIC, TIFF, WebP, GIF, rotated JPEGs and oversized images are re-encoded (JPEG at quality 0.88 if opaque, PNG if transparent), and PDFs render their first page as PNG. Everything is stored in the board's asset table, deduplicated by SHA‑256.

### 4.4 Web card

- Sources: paste a URL, drag a link from Safari or Chrome, drop a `.webloc` file, or `Insert ▸ Link…` (⌘L).
- Renders a **rich link preview** (§7): hero image, gradient wash taken from the page's own colors, favicon, site name, title, description and domain chip.
- Click once to select it. Double-click (or ⌘↩) to open it in the default browser. Press Space to **Peek** a live view (§7.7).
- The preview is **snapshotted into the file**, so it renders offline with no network.
- `Refresh Preview` (⌘R) fetches the page again on demand.

### 4.5 Strings ("connect the dots")

- Drag from any card's pin to another card to create a string.
- **Rendering**: a cubic Bézier with physical-looking **sag**, a subtle twisted-thread texture, and a 2‑stop gradient along its length. On creation it animates in as a "pull taut" spring (§6.6).
- **Properties**: color (Evidence Red by default), thickness (1–4 pt), sag (0 = taut, 1 = loose), style (solid, dashed or dotted), arrow (none, forward or both) and **label**. The label is a small glass capsule at the midpoint.
- **Multiple strings** between the same two cards fan out with different sag values so they never overlap.
- Strings follow their cards live while you drag, at 120 fps.
- **Trace mode** (⌘T with two cards selected) finds the shortest chain of strings between them. It highlights that path with a travelling glow pulse and dims everything else to 25%. This is the core "connect the dots" moment.
- **Focus mode** (F with one card selected) highlights the card, its direct neighbours and their strings, and dims the rest. Press F again to widen by one more hop.

### 4.6 Organisation helpers (no new card types)

- Multi-select, align and distribute (inspector or ⌥⌘ arrow keys).
- Smart **alignment guides** while dragging (magenta hairlines, snap within 6 pt).
- **Lock** a card (it becomes un-draggable and its pin turns brass).
- **Z-order**: bring to front and send to back. Cards you're dragging always float to the top temporarily.
- **Search** (⌘F) across text, captions, link titles, site names, descriptions and URLs. Every word must match, ignoring case and accents. Matches glow in the selection color, non-matches dim, and ↩ (or ⌘G, ⇧⌘G back) moves to the next match, selecting it and bringing it into view at a readable zoom. Esc closes it.

### 4.7 Documents

- Standard Mac document app: New, Open, Open Recent, Save, Save As, Duplicate, Revert to Saved, autosave and Versions (from `DocumentGroup` / `NSDocument`).
- **Export**: PNG or PDF of the whole board or the selection (rendered at 2× by default). **Export as JSON** is the native format itself.
- **Import**: any valid board JSON, including files written by hand or by scripts (the schema is in `docs/schema/`).

---

## 5. Interaction design

### 5.1 Window layout

```
┌───────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Case 042 — The Harbor Files       [V][T][C][H]   ⌕   ◐   ⓘ      │ ← unified toolbar (glass)
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│        ┌──────────┐                          ┌───────────────┐            │
│        │  ● Note  │╲                         │ ●  ▓▓▓▓▓▓▓▓▓▓ │  ┌───────┐ │
│        │          │ ╲___________             │    ▓▓ hero ▓▓ │  │Inspec-│ │
│        └──────────┘             ╲____________│ nytimes.com   │  │ tor   │ │ ← floating glass panel
│                    ┌────────┐                │ Title of the… │  │(⌥⌘I)  │ │   (hidden by default)
│                    │ ●      │________________└───────────────┘  └───────┘ │
│                    │ [img]  │                                             │
│                    └────────┘                                  ┌───────┐  │
│ ┌──────────────┐                                               │minimap│  │
│ │ −   72%   +  │                                               └───────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

- **Toolbar** (from left): document title (with rename on click), a tool segmented control (Select V, Connect C, Hand H), then New Text Card, Add Link, Search and the Theme menu. *(As built in M5; the Text tool is the T key and the New Text Card button, and the Inspector toggle arrives with the inspector.)*
- There's no sidebar. The board fills the window edge to edge, under a transparent title bar (`.windowStyle(.hiddenTitleBar)` with toolbar, full-size content view).
- The **inspector** is a floating glass panel docked top-right, 280 pt wide. It's contextual and shows the properties of the current selection.

### 5.2 Creating things

| Action | Result |
|---|---|
| Double-click empty canvas | New **Text** card at that point, already in edit mode |
| Text tool (T) + click | Same as above |
| ⌘V with an image on the pasteboard | **Image** card at the cursor (or the viewport center) |
| ⌘V with a URL | **Web** card. A skeleton shimmer shows until the preview resolves |
| ⌘V with plain text | **Text** card. If the text is exactly one URL, a Web card |
| Drop files, images, URLs or text | The matching card at the drop point. Several items spread in a fan cascade |
| ⌘⇧V | Paste as plain text (forces a Text card, even for a URL) |

### 5.3 Moving and selecting

- Click selects. ⇧‑click adds or removes. Dragging on empty canvas draws a **marquee** (it intersects, and holding ⌥ switches it to contains).
- Drag to move. Selected cards lift: scale 1.02, deeper shadow, and the pin pops slightly.
- Arrow keys nudge 1 pt, and ⇧ + arrow nudges 10 pt.
- Resize handles appear on hover over a selected card's corners. Hold ⇧ to keep the aspect ratio (the default for images).
- **Tilt**: ⌥ + drag a corner handle rotates the card (±8° is a natural range; snaps at 0°). New cards get a tiny random tilt of ±1.5° when "Natural tilt" is on in Settings, which is off by default.

### 5.4 Navigating

| Input | Action |
|---|---|
| Two-finger scroll / mouse wheel | Pan |
| Pinch / ⌘ + scroll | Zoom around the cursor |
| Space + drag, middle-drag, Hand tool | Pan |
| ⌘0 | Zoom to fit all cards |
| ⌘1 | 100% |
| ⌘2 | Zoom to selection |
| ⌘+ / ⌘− | Zoom in or out in steps |
| Click the minimap | Jump to that spot |

Panning and zooming use **momentum** with rubber-band-free infinite bounds. Zoom steps animate with a spring of 0.28 s.

### 5.5 Connecting

1. Hover a card and its **pin** brightens and grows 1.15×.
2. Drag from the pin. A live string follows the cursor with real sag and a soft magnetic pull.
3. When you hover a target card, the target's pin pulses and the string **snaps** to it (spring).
4. Release to create the string, with a "pull taut" animation and a haptic tap (`NSHapticFeedbackManager`, `.alignment`).
5. Release on empty canvas to cancel. The string retracts back into the pin.

Shortcuts: with the **Connect tool (C)**, drag from anywhere on a card, not only the pin. You can also select exactly two cards and press **⌘K**.

Strings: click to select (the hit area is 10 pt wide around the curve), Delete to remove, double-click to edit the label, and drag the midpoint to adjust sag.

### 5.6 Undo

Every mutation is undoable: create, delete, move, resize, rotate, edit, restyle, connect and disconnect. A drag is **one** undo step. A multi-card paste is one undo step.

---

## 6. Visual design system

The default theme is **Noir**: a night-time detective office, deep ink-blue darkness, glass cards catching light, and string that glows red against the dark.

### 6.1 Color tokens: Noir (default, dark)

| Token | Value | Use |
|---|---|---|
| `bg.top` | `#0B0E17` | Board gradient, top-left |
| `bg.bottom` | `#151A2C` | Board gradient, bottom-right |
| `bg.vignette` | `#000000` at 45% | Radial edge darkening |
| `bg.grid` | `#FFFFFF` at 6% | Dot grid (1.4 pt dots, 24 pt pitch, fades out below 40% zoom) |
| `card.fill` | `#1B2133` → `#141927` | Card body gradient (top → bottom) |
| `card.stroke` | `#FFFFFF` 14% → 3% | 1 pt inner border gradient (light from above) |
| `card.highlight` | `#FFFFFF` 8% | 1 pt top inner highlight line |
| `text.primary` | `#F2F4FA` | |
| `text.secondary` | `#A7AEC2` | |
| `text.tertiary` | `#6B7390` | |
| `accent.string` | `#FF3B4E` → `#FF7A59` | Default string gradient (Evidence Red) |
| `accent.select` | `#5B8CFF` → `#9B6BFF` | Selection ring gradient |
| `accent.pin` | `#FF4757` radial → `#B3121F` | Push-pin head |
| `accent.pin.locked` | `#E9C46A` → `#A6802B` | Brass pin for locked cards |
| `guide` | `#FF4FD8` | Alignment guides |

**Tint palette** (cards and strings), each a 2-stop gradient:

| Name | From | To |
|---|---|---|
| Evidence Red | `#FF3B4E` | `#FF7A59` |
| Amber | `#FFB547` | `#FF8A3D` |
| Lime | `#A8E063` | `#56AB2F` |
| Teal | `#2AF5D2` | `#0BA5A5` |
| Azure | `#4FACFE` | `#3A6BFF` |
| Violet | `#A97CFF` | `#6A3DF0` |
| Rose | `#FF7EB3` | `#E0457B` |
| Graphite | `#B8C0D6` | `#7D86A0` |

### 6.2 Other themes

Every theme is a `Theme` value with the same token set, so you can switch live (⌥⌘T, `Board ▸ Theme` or the toolbar ◐ menu). The theme is saved per board, and switching is one undoable step that cross-fades the whole board in 0.4 s.

| Theme | Mood | Background | Cards | String |
|---|---|---|---|---|
| **Noir** (default) | Night office | Ink-blue gradient + vignette + dots | Dark glass | Evidence Red |
| **Cork** | Classic corkboard | Warm `#7A5634` → `#5E3F22` + procedural cork grain | Off-white paper, warm shadow | Deep red wool |
| **Blueprint** | Engineering | `#0D3B66` → `#08284A` + 1 pt line grid | Translucent blue glass, white text | White / cyan |
| **Daylight** | Light mode | `#F5F6FA` → `#E7EAF3` + soft dots | White with 1 pt hairline | Red, slightly desaturated |

The app follows the system appearance by default (**Automatic**: **Noir** in dark mode and **Daylight** in light mode). A board that sets an explicit theme keeps it, and its window takes that theme's light or dark appearance.

**As built (M5).** Each theme also sets the card shadow color and strength (warm brown on Cork, softer on Daylight) and its own string color, used for strings left at the default Evidence Red: deep red wool on Cork, white to cyan on Blueprint, a quieter red on Daylight. The textures are drawn in view space by replicator layers, like the dot grid: Blueprint's 24 pt drafting grid has a heavier line every fifth and doubles its pitch when it would get dense; Cork's grain is one seamless, seeded 256 pt tile drawn once per theme, which moves with the board but keeps its size when you zoom, so it never pixelates. Light themes get deeper tints so colors hold up on paper, and web card text picks its ink against the mesh it actually sits on.

### 6.3 Typography

| Role | Font | Size / weight | Tracking |
|---|---|---|---|
| Headline card | SF Pro Display | 28 / Bold | −0.4 |
| Note card | SF Pro Text | 15 / Regular, line height 1.4 | 0 |
| Typewriter card | SF Mono | 14 / Regular | 0 |
| Web title | SF Pro Display | 17 / Semibold, 2 lines | −0.2 |
| Web description | SF Pro Text | 13 / Regular, 3 lines | 0 |
| Web site name, domain | SF Pro Text | 11 / Semibold, uppercase | +0.6 |
| String label | SF Pro Rounded | 11 / Medium | 0 |
| Image caption | New York (serif) | 13 / Italic | 0 |

All type uses Dynamic Type-equivalent scaling through the app's *Text Size* setting (Small, Default, Large or XL).

### 6.4 Materials, depth and shadows

Cards have **three stacked shadows**, which is what makes them feel "pinned on" rather than flat:

| Layer | Offset | Blur | Color |
|---|---|---|---|
| Contact | (0, 1) | 2 | black 35% |
| Mid | (0, 6) | 14 | black 28% |
| Ambient | (0, 18) | 40 | black 22% |

- When a card is lifted (dragging), the shadows interpolate to offsets ×1.8 and blur ×1.6.
- Every shadow uses an explicit `shadowPath` (§10.4), so it's never computed from alpha.
- **Glass** (toolbar, inspector, minimap, HUD, string labels): `.ultraThinMaterial` on macOS 15, and `.glassEffect()` (Liquid Glass) on macOS 26+ behind `if #available`.
- **Card corner radius**: 14 pt (continuous / squircle curve). Image cards with the Borderless frame use 10 pt.

### 6.5 The pin

A pin is a 14 pt sphere drawn with a radial gradient (highlight at top-left), a 1 pt dark rim and a 3 pt drop shadow offset (2, 3) that suggests the needle. It sits centered 10 pt below the card's top edge. Strings attach to the pin center.

### 6.6 Motion

All motion uses springs. Nothing is linear except the shimmer.

| Moment | Animation |
|---|---|
| Card appears | Scale 0.92 → 1.0, opacity 0 → 1, y +8 → 0. Spring(response 0.35, damping 0.78) |
| Card pinned (drop) | Scale 1.02 → 1.0 with shadow settle. Spring(0.3, 0.7) |
| String created | Path `strokeEnd` 0 → 1 over 0.22 s, then sag overshoots 1.25× → 1.0 (spring 0.45, 0.6) |
| String deleted | Snaps: `strokeStart` → 1 over 0.15 s, ease-in |
| Trace pulse | A 60 pt glow segment travels along the path at 600 pt/s, repeating while Trace mode is on |
| Link preview resolves | Skeleton shimmer cross-fades to content (0.25 s). The hero fades in when it's decoded (0.3 s; a blur-in may follow) |
| Selection ring | Gradient ring rotates slowly (12 s per revolution) while selected |
| Theme switch | 0.4 s cross-fade of the background, with token animations on every card |

**Reduce Motion**: every spring becomes a 0.15 s fade, there's no pulse, rotating rings or blur-in, and Trace shows the path statically.

**As built (M5).** Card springs are `CASpringAnimation`s made to match SwiftUI's `spring(response:dampingFraction:)`. Cards pop in only when up to 40 arrive at once, so a big paste or the test boards don't animate hundreds of cards. Search matches glow with a soft halo in the selection color, stronger on the match being shown.

### 6.7 App icon

A squircle in Noir ink gradient, three glossy card silhouettes at slight angles, and one red string pulled diagonally between two red pins. Light-mode and tinted variants come from the Icon Composer layered file (`AppIcon.icon`) for macOS 26, with a classic `AppIcon.appiconset` fallback. *(As built: the `AppIcon.appiconset` ships; the layered `AppIcon.icon` needs Icon Composer on a Mac and is still to come.)*

---

## 7. Rich link previews

The signature feature. A Web card should look like the cover of a magazine story about that page, not like a grey bookmark.

### 7.1 Card anatomy (Hero variant, 360 pt wide)

```
╭────────────────────────────────────────╮  ← 14 pt radius, gradient border from page palette
│ ●                                      │  ← pin
│ ┌────────────────────────────────────┐ │
│ │                                    │ │
│ │           HERO IMAGE  (16:9)       │ │  ← og:image, downsampled, aspect-fill
│ │                                    │ │
│ │░░░░░░░░░ palette gradient wash ░░░░│ │  ← bottom 45%: transparent → dominant dark swatch
│ └────────────────────────────────────┘ │
│  [◉] THE VERGE · theverge.com          │  ← favicon squircle + site name + domain
│  Inside the race to build the          │  ← title, 2 lines, semibold
│  perfect detective game                │
│  A look at how a small studio turned   │  ← description, 3 lines, secondary
│  thousands of clues into one board…    │
│                               ↗ Open   │
╰────────────────────────────────────────╯
     ░░░ ambient glow: blurred hero, 35% ░░░   ← behind the card, bleeds onto the board
```

**What makes it high quality:**

1. **Palette-driven gradients.** We take 5 swatches from the hero image (or the favicon, or `theme-color`) (§7.4). The card body fill is a **3×3 mesh gradient** between the theme card color and the swatches, so every link card has its own color signature while still matching the board. It's drawn once as a 32 px bitmap with smoothstep blending and stretched by Core Animation with linear filtering, which looks the same as a `MeshGradient` at any zoom and costs nothing to redraw.
2. **Ambient glow.** A heavily blurred (Core Image Gaussian on a 64 px copy), 1.15× scaled copy of the hero sits behind the card at 35% opacity and fades out at its edges, like Apple Music's backdrop. It's made once per decoded hero.
3. **Gradient border.** A 1 pt stroke from the vibrant swatch at 60% (top) to 0% (bottom).
4. **Legible overlays.** Text over the image always gets a scrim: a gradient from transparent to the dark muted swatch at 85%. A contrast check (WCAG ≥ 4.5:1) picks light or dark text.
5. **Crisp images.** Images are decoded off the main thread at exactly the display pixel size (§10.5).

### 7.2 Layout variants

The variant is chosen automatically from the metadata:

| Variant | When | Look |
|---|---|---|
| **Hero** | An image ≥ 600 px wide with aspect 1.2–2.4 | As above |
| **Portrait** | An image with aspect < 1.2 (posters, books, products) | Image down the left (up to 132 pt wide, the full height of the card), text on the right, mesh-gradient background |
| **Media** | `og:type` is `video.*`, or YouTube/Vimeo/oEmbed video | Hero, plus a frosted play button and a duration badge (from oEmbed or JSON‑LD `duration`) |
| **Social** | X, Bluesky, Mastodon, Threads, Reddit (by domain or `og:type`) | Avatar + author, then the post text as a large quote, then media below if any |
| **Article** | JSON‑LD `Article` or `NewsArticle` | Hero, plus a byline row (author · date · reading time) |
| **Compact** | No usable image | A full-card **mesh gradient** from favicon / theme-color swatches, a big favicon (48 pt squircle) and the title in Display 20 Bold. It still looks premium without any photo |
| **Fallback** | Metadata fetch failed | Compact layout, a generated gradient from a hash of the domain, the title = the URL host, and a small "Preview unavailable · ⌘R to retry" note |

### 7.3 Metadata pipeline

```
URL ─▶ normalize ─▶ cache? ──hit──▶ render
                      │ miss
                      ▼
          ┌───────────┴────────────┐          (both in parallel, 10 s timeout)
          ▼                        ▼
 LPMetadataProvider        HTMLHeadFetcher (URLSession)
 (title, icon, image,      GET, stream ≤ 512 KB, stop at </head>
  video, remote URL)       parse og:*, twitter:*, <title>, meta description,
                           theme-color, link rel=icon/apple-touch-icon,
                           JSON-LD (Article/VideoObject/Person), oEmbed link
          └───────────┬────────────┘
                      ▼
               MetadataMerger  ── choose best title / description / image / icon
                      ▼
               ImageFetcher    ── download best image + icon, ImageIO downsample
                      ▼
               PaletteExtractor ── 5 swatches (vibrant, muted, dark-vibrant, dark-muted, light)
                      ▼
               LinkSnapshot    ── stored in board assets + disk cache ─▶ render
```

Details:

- **Normalize**: lowercase the host, strip the fragment, optionally strip tracking parameters (`utm_*`, `fbclid`, `gclid`, `si`; a setting that's on by default), and upgrade `http` to `https` when possible.
- **Merger priority**: Title is `og:title` › `twitter:title` › JSON‑LD `headline` › LP title › `<title>`. For the image, take every candidate (`og:image`, `twitter:image`, JSON‑LD image, LP image) and score it by *declared size ≥ 600 px*, *aspect closest to 1.91:1* and *not an SVG logo*.
- **Icon**: the largest of `apple-touch-icon` › `icon` with sizes › LP icon › `/favicon.ico`.
- **Rate limiting**: at most 4 concurrent fetches per board, and at most 1 per host.
- **User agent**: a desktop Safari UA string, which gets the richest OG tags from most sites.
- No JavaScript is ever executed (§13). Sites that render metadata only client-side fall back to LP results.

**As built (M4).** All of this lives in the `LinkPreviewKit` package. The pure parts (URL normalizing, head parser, JSON‑LD, merger, variant rules, palette, cache) build and test on Linux too; the fetching parts (`PageFetcher`, `LPMetadataProvider`, ImageIO) are Darwin-only. `LinkPreviewService.shared` is an actor that runs the pipeline and never throws: when anything fails it returns the **Fallback** preview. The limits (4 fetches at once, 1 per host) are app-wide. The canvas turns the downloaded images into board assets (hero up to 1600 px, icon up to 256 px) off the main thread. The first preview of a new card is part of adding it, so it doesn't get its own undo step; it only marks the document edited. A refresh is its own undoable step, and a refresh that fails keeps the old snapshot and says so.

### 7.4 Palette extraction

```swift
/// Extracts 5 role-based swatches from an image. Runs off the main actor (~2 ms).
struct PaletteExtractor {
    func palette(for image: CGImage) -> LinkPalette {
        // 1. Downsample to 64×64 into an sRGB bitmap (CGContext, .low interpolation).
        // 2. Convert pixels to OKLab and skip near-transparent pixels.
        // 3. k-means (k = 8, 6 iterations, k-means++ seeding) in OKLab.
        // 4. Score clusters into roles by population, chroma and lightness:
        //      vibrant      = high chroma, L 0.45–0.75
        //      muted        = low chroma,  L 0.35–0.65
        //      darkVibrant  = high chroma, L < 0.40
        //      darkMuted    = low chroma,  L < 0.35   (scrim / text backdrop)
        //      light        = L > 0.80                 (light-on-dark text tint)
        // 5. Fill any missing role by shifting lightness of the nearest found swatch.
    }
}
```

The palette is stored in the snapshot, so it's never recomputed on load.

### 7.5 Loading states

- **Skeleton**: the card renders at its final size immediately, with a shimmering gradient sweep (1.2 s loop) over placeholder bars. You can move and connect it at once.
- **Arrival**: the finished preview replaces the skeleton in one step, and the card takes the height its layout needs. Images then decode at display size (§10.5); until the favicon arrives, a monogram on the palette color stands in for it.
- *(Planned)* **Progressive**: show the title and favicon first and the hero when it's decoded. M4 waits for the whole preview, which is simpler and usually fast enough.

### 7.6 Caching

| Layer | Contents | Policy |
|---|---|---|
| **Board assets** | Snapshot (metadata + palette) in the card's `web` field. Hero and icon bytes in `assets` | Permanent, travels with the file |
| **Disk cache** | `~/Library/Caches/<bundle>/LinkPreviews/<fnv1a(url)>.json` + images | 30‑day LRU, 500 MB cap |
| **Memory** | `NSCache` of decoded `CGImage` per (assetID, pixelSize) | Evicted on memory pressure |

**Opening a board never touches the network.** Previews come from the snapshot. Refresh is only ever explicit (⌘R on a card, or `Board ▸ Refresh All Previews`).

### 7.7 Peek (live view on demand)

Tap Space (press and release without panning) on a selected Web card to open a **popover** (720×520) with a `WKWebView` (non-persistent data store, no access to the user's cookies) loading the page. It closes on Esc. The web view is created lazily and torn down on close. No `WKWebView` ever lives on the canvas itself, which is critical for memory and scroll performance.

---

## 8. File format (JSON)

### 8.1 Goals

- **One self-contained file**: text, layout, strings, images and link snapshots.
- **Human-readable and diff-friendly**: pretty-printed, sorted keys, stable IDs, with large binary data isolated in the `assets` table at the end of the file.
- **Scriptable**: anyone can generate a board from Python or JS. Unknown fields are preserved.
- **Versioned**: `formatVersion` plus forward migrations.

### 8.2 File type

| | |
|---|---|
| Extension | `.evboard` (opening plain `.json` is also supported) |
| UTI | `com.evidenceboard.board`, conforms to `public.json`, `public.data`, `public.content` |
| MIME | `application/vnd.evidenceboard+json` |
| Encoding | UTF‑8, LF line endings, 2-space indent, `sortedKeys` |

### 8.3 Top-level structure

```jsonc
{
  "format": "evidenceboard",          // magic string, always this value
  "formatVersion": 1,                  // integer, bumped on breaking change
  "id": "6F1C…",                       // board UUID
  "title": "Case 042 — The Harbor Files",
  "createdAt": "2026-10-14T09:12:44Z", // ISO-8601 UTC
  "modifiedAt": "2026-10-14T11:40:02Z",
  "theme": "noir",                     // noir | cork | blueprint | daylight | system
  "viewport": { "x": 0, "y": 0, "zoom": 1.0 },   // world point at window center
  "cards": [ /* Card */ ],
  "strings": [ /* String */ ],
  "assets": { /* assetID → Asset */ }
}
```

### 8.4 Card

Common fields for every card:

```jsonc
{
  "id": "A1B2…",               // UUID
  "type": "text",              // "text" | "image" | "web" — nothing else is valid
  "frame": { "x": -220, "y": -140, "width": 260, "height": 160 },  // world space, top-left origin, y grows downward
  "rotation": -1.5,            // degrees, clamped to [-15, 15]
  "z": 12,                     // stacking order (higher is in front)
  "tint": "red",               // optional palette name
  "locked": false,
  "createdAt": "…", "modifiedAt": "…",

  // exactly one of these payloads, matching "type":
  "text":  { … },
  "image": { … },
  "web":   { … }
}
```

**Text payload**

```jsonc
"text": {
  "content": "Ferry left **11 minutes early** on the 3rd.",
  "style": "note",            // note | headline | typewriter
  "alignment": "leading",     // leading | center | trailing
  "autoHeight": true
}
```

**Image payload**

```jsonc
"image": {
  "asset": "sha256-9f86d0…",                     // key into "assets"
  "caption": "Dock camera, 23:41",
  "frameStyle": "polaroid",                     // polaroid | borderless | photo
  "crop": { "x": 0.0, "y": 0.1, "width": 1.0, "height": 0.8 }  // normalized, optional
}
```

**Web payload**

```jsonc
"web": {
  "url": "https://example.com/harbor-report",
  "snapshot": {                                  // optional; absent until first fetch
    "fetchedAt": "2026-10-14T09:20:00Z",
    "variant": "hero",                           // hero | portrait | media | social | article | compact | fallback
    "title": "Harbor authority releases night logs",
    "description": "The logs show three unscheduled departures…",
    "siteName": "Example News",
    "author": "J. Rivera",
    "publishedAt": "2026-10-12T00:00:00Z",
    "mediaDuration": null,                       // seconds, for video
    "image": "sha256-2c26b4…",                   // asset id, optional
    "icon": "sha256-fcde2b…",                    // asset id, optional
    "palette": {
      "vibrant": "#3A7BFF", "muted": "#5C6A88",
      "darkVibrant": "#12306E", "darkMuted": "#1B2235", "light": "#E8EEFF"
    }
  }
}
```

### 8.5 String

```jsonc
{
  "id": "C3D4…",
  "from": "A1B2…",                 // card id
  "to":   "E5F6…",                 // card id
  "color": "red",                  // palette name or "#RRGGBB"
  "thickness": 2.0,                // 1–4 pt
  "sag": 0.5,                      // 0 taut … 1 loose
  "style": "solid",                // solid | dashed | dotted
  "arrow": "none",                 // none | forward | both
  "label": "same boat?"            // optional
}
```

### 8.6 Asset

```jsonc
"assets": {
  "sha256-9f86d0…": {
    "mime": "image/jpeg",
    "pixelWidth": 3024, "pixelHeight": 4032,
    "byteCount": 1843211,
    "data": "/9j/4AAQSkZJRgABAQ…"   // base64 (standard alphabet, no line breaks)
  }
}
```

- The asset ID is `sha256-` followed by the hex digest of the raw bytes, so identical images are stored once.
- Unreferenced assets are garbage-collected on save.

### 8.7 Validation and robustness

On load, the `BoardLoader`:

1. Checks `format == "evidenceboard"`. Plain JSON without it is rejected with a friendly error.
2. Runs migrations `v(n) → v(n+1)` if `formatVersion` is older. A *newer* version opens read-only with a banner.
3. **Skips** any card whose `type` isn't text, image or web, and any card whose payload doesn't match its type. The app shows a non-blocking banner: "2 items couldn't be loaded".
4. Drops strings whose `from` or `to` card is missing, and self-loops.
5. Clamps out-of-range numbers (zoom, rotation, thickness, sag).
6. Keeps unknown *fields* in a `[String: JSONValue]` side-table and writes them back on save, for forward compatibility.

A full JSON Schema (draft 2020-12) is in [`docs/schema/evidenceboard.schema.json`](schema/evidenceboard.schema.json), and a sample board is in [`docs/examples/harbor-case.evboard`](examples/harbor-case.evboard).

### 8.8 Size considerations

Base64 adds about 33%. A board with 200 phone photos (downsampled to 4096 px, roughly 1.5 MB each) comes to about 400 MB of JSON, which is acceptable but slow to parse. Mitigations:

- Import downsampling (the default cap of 4096 px, which can go down to 2048 px).
- Re-encoding opaque images as JPEG at quality 0.88 when that's smaller than the original. HEIC is converted to JPEG for portability.
- Assets sit in a separate top-level object and are decoded **lazily**. The loader parses the structure first and keeps `assets.*.data` as raw `Substring` ranges, decoding base64 only when an image first needs to be shown (§10.5).
- *Future:* an optional `.evboardpkg` package format (a folder with `board.json` + `assets/`) for very large boards. The JSON shape stays identical, and `data` becomes a relative `path`.

---

## 9. Architecture

### 9.1 Layers

```
┌──────────────────────────────────────────────────────────────┐
│ App (SwiftUI)        EvidenceBoardApp · DocumentGroup · Commands · Settings
├──────────────────────────────────────────────────────────────┤
│ Feature UI (SwiftUI) Toolbar · Inspector · Minimap · ZoomHUD · Search · Peek
│                      Card views: TextCardView · ImageCardView · WebCardView
├──────────────────────────────────────────────────────────────┤
│ Canvas Engine        BoardCanvasView (NSView, layer-hosting)
│ (AppKit + CA)        Camera · NodeLayerPool · StringRenderer · HitTester
│                      Gesture/Tool state machine · LOD manager
├──────────────────────────────────────────────────────────────┤
│ Domain               BoardStore (@MainActor) · BoardCommand (undoable) · BoardClip
│                      SpatialGrid · GraphQueries (focus/trace)
├──────────────────────────────────────────────────────────────┤
│ Services (actors)    LinkPreviewService · ImagePipeline · PaletteExtractor
│                      AssetStore · BoardCodec (JSON) · Migrations
└──────────────────────────────────────────────────────────────┘
```

### 9.2 Key types

```swift
// MARK: Model (value types, Codable)

struct Board: Codable, Sendable {
    var format = "evidenceboard"
    var formatVersion = 1
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var theme: ThemeID
    var viewport: Viewport
    var cards: [Card]
    var strings: [BoardString]
    var assets: [AssetID: Asset]
}

struct Card: Codable, Identifiable, Sendable {
    var id: UUID
    var frame: CGRect
    var rotation: Double
    var z: Int
    var tint: TintName?
    var locked: Bool
    var createdAt: Date
    var modifiedAt: Date
    var content: CardContent          // custom Codable → "type" + matching payload key
}

enum CardContent: Sendable {
    case text(TextPayload)
    case image(ImagePayload)
    case web(WebPayload)
}

struct BoardString: Codable, Identifiable, Sendable {
    var id: UUID
    var from: UUID
    var to: UUID
    var color: StringColor
    var thickness: Double
    var sag: Double
    var style: StrokeStyleKind
    var arrow: ArrowKind
    var label: String?
}

// MARK: Store (BoardKit, Foundation only, so it's tested on Linux too)

@MainActor
final class BoardStore {
    private(set) var board: Board
    var viewport: Viewport                     // camera; never marks the document as edited

    /// The single mutation entry point. Returns the inverse command, or nil if nothing changed.
    func apply(_ command: BoardCommand) -> BoardCommand?
    func addObserver(_ observer: @escaping @MainActor (BoardChanges) -> Void) -> UUID
    var graph: BoardGraph { get }              // rebuilt lazily after string edits
}

/// Strings as an undirected graph of cards, for Focus and Trace. Card IDs map to array
/// indices once; searches are plain BFS over arrays.
struct BoardGraph: Sendable {
    init(strings: [BoardString])
    func neighborhood(of seeds: Set<UUID>, hops: Int) -> Neighborhood  // cards, strings, canWiden
    func shortestPath(from: UUID, to: UUID) -> GraphPath?              // cards[i] —strings[i]— cards[i+1]
}

// MARK: Commands (every mutation is one, so undo is free)

enum BoardCommand: Sendable, Equatable {
    case insertCards([Card], positions: [Int]? = nil)    // positions restore file order on undo
    case removeCards(Set<UUID>)                          // also removes their strings
    case insertStrings([BoardString], positions: [Int]? = nil)
    case removeStrings(Set<UUID>)
    case updateStrings([BoardString])                    // color, label, sag, arrow, direction
    case setFrames([UUID: Rect])                         // move and resize
    case updateCards([Card])                             // text, style, tint, z, lock
    case addAssets([AssetID: Asset])
    case removeAssets(Set<AssetID>)
    case batch([BoardCommand])
}

struct BoardChanges {                                    // exactly what changed
    var insertedCards, updatedCards, removedCards: Set<UUID>
    var insertedStrings, updatedStrings, removedStrings: Set<UUID>
}
```

`apply(_:)` mutates `board`, computes the inverse command and notifies observers with a `BoardChanges`. The canvas updates only those cards and strings and **never** diffs the whole board. Undo lives one level up, in CanvasKit's `BoardEditor`: it registers each inverse with the document's `UndoManager` (from the SwiftUI environment), which is also how a SwiftUI document learns it has unsaved changes. Selection is canvas state, not document state, so it's never undone.

### 9.3 Document integration

```swift
@main
struct EvidenceBoardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { BoardDocument() }) { config in
            BoardWindow(document: config.document)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands { BoardCommands() }

        Settings { SettingsView() }
    }
}

final class BoardDocument: ReferenceFileDocument {
    static let readableContentTypes: [UTType] = [.evidenceBoard, .json]
    static let writableContentTypes: [UTType] = [.evidenceBoard]

    @MainActor let store: BoardStore

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        store = BoardStore(board: try BoardCodec.decode(data))   // lazy assets (§8.8)
    }

    func snapshot(contentType: UTType) throws -> Board { store.board }   // cheap: value copy (CoW)

    func fileWrapper(snapshot: Board, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BoardCodec.encode(snapshot))  // runs off main
    }
}

extension UTType {
    static let evidenceBoard = UTType(exportedAs: "com.evidenceboard.board", conformingTo: .json)
}
```

Saving a value-type snapshot keeps the main thread free. Encoding (including base64 of new assets) happens on the background writer thread. Asset base64 strings are **cached** after the first encode, so later saves only stream bytes.

### 9.4 Concurrency model

- `BoardStore`, the canvas and all UI run on `@MainActor`.
- `LinkPreviewService`, `ImagePipeline` and `AssetStore` are **actors**. Results return to the main actor as `BoardCommand.updateCard`.
- Link fetches are cancellable `Task`s keyed by card ID. Deleting a card cancels its fetch.
- Swift 6 strict concurrency is on (`SWIFT_STRICT_CONCURRENCY = complete`), and every model type is `Sendable`.

---

## 10. Canvas rendering engine

**Decision:** the canvas is a custom **layer-hosting `NSView`** wrapped in `NSViewRepresentable`, not a SwiftUI `ZStack`. Pure SwiftUI re-evaluates view bodies on every transform change and can't hit 120 fps with hundreds of shadowed, gradient-filled cards. Core Animation can, because pan and zoom then become a single GPU transform.

### 10.1 Layer tree

```
BoardCanvasView.layer (root)
├── backgroundLayer      CAGradientLayer + procedural texture layer (screen-space, never transformed)
├── gridLayer            CAReplicatorLayer dots, re-pitched at zoom tiers
├── worldLayer           ◀── sublayerTransform = camera (scale + translate) — the ONLY thing pan/zoom changes
│   ├── cardsLayer       one CardLayer per card, stacked by zPosition = z
│   │     dimLayer        Focus/Trace: one translucent layer over the cards; highlighted cards are raised above it
│   │     CardLayer
│   │       ├── shadowLayers  (3 shadows, explicit shadowPath)
│   │       ├── bodyLayer     (gradient fill, tint band, placeholder bars)
│   │       ├── contentLayer  (card content as a bitmap for the current zoom tier)
│   │       ├── strokeLayer   (gradient border)
│   │       └── pinLayer      (inside the card, so a card on top covers the pins below it)
│   ├── stringsLayer     one string per layer above every card, with a knot over each pin,
│   │                    plus the live connect string and the Trace pulse
│   └── selectionLayer   selection rings (world space, re-thickened when the zoom settles)
├── overlayLayer         resize handles, the string grip, marquee, guides (screen-space)
└── HUD (SwiftUI)        toolbar, minimap, zoom HUD, inspector, which are separate NSHostingViews
```

The canvas sits in a plain host view. A layer-hosting view can't have subviews, so things that must be real views, like the text editor, are siblings above it in the host.

### 10.2 Camera

- `Camera { center: CGPoint (world), zoom: CGFloat }` produces a `CATransform3D` assigned to `worldLayer.sublayerTransform` inside `CATransaction.setDisableActions(true)`.
- Pan and zoom **never** relayout cards or re-render content. They change one matrix.
- Zoom anchors on the cursor: `center' = cursorWorld − (cursorWorld − center) · (zoom / zoom')`.

### 10.3 Card content: snapshot-at-rest

Card chrome (body, shadows, stroke, pin) is plain Core Animation, so it stays sharp at any zoom for free. Only the content is a bitmap:

1. **Text cards** are drawn with TextKit (`NSAttributedString` into a bitmap context, about 0.2–0.5 ms per card) at `frameSize × zoomTier × backingScale`, capped at 4096 px on the long side, and set as `contentLayer.contents`. **Web cards** work the same way: `WebCardLayout` places everything for the card's variant and width, all of the card's text is drawn into one TextKit bitmap per tier, and the pictures (mesh, glow, hero, favicon, play button, badge, skeleton shimmer) are plain layers. SwiftUI's `ImageRenderer` turned out not to be needed, and staying with Core Animation keeps web cards as cheap as text cards.
2. Zoom tiers are **0.25, 0.5, 1, 2 and 4**. The tier follows the zoom once the zoom has been still for 160 ms, so a pinch never redraws every card per frame. Until then the old bitmap is scaled.
3. Bitmaps are drawn by a **render queue** that spends at most 5 ms of each frame, nearest cards first, and only for cards within 25% of the viewport. Bitmaps of cards more than a screen away are freed.
4. While a text card is **being edited**, its bitmap is hidden and a live `NSTextView` (inside an `NSScrollView` whose magnification equals the zoom) sits over the card, using exactly the same attributes, so no line moves when editing starts or ends.
5. A card re-renders only when its content, size, theme or tier changes. Moving it never re-renders anything.

### 10.4 Level of detail (LOD)

| Zoom | Card rendering | Strings | Shadows | Pins |
|---|---|---|---|---|
| ≥ 40% | Full snapshot | Gradient + texture + labels | 3-layer | Full |
| 15–40% | Snapshot at tier 0.25 | Solid color, no labels | 1 layer | Simple dot |
| < 15% | Flat rounded rect (body only) | Hairline | None | None |

Other rules:

- `shadowPath` is always set explicitly (it's a rounded rect from the frame). Without this, Core Animation renders shadows off-screen per frame, which is the #1 performance trap.
- `shouldRasterize` stays **off** for card layers (contents are already bitmaps) and **on** for string label capsules.
- `drawsAsynchronously = true` on texture layers.

### 10.5 Image pipeline

- **Decode**: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` set to the needed pixel size (photo size × tier × backing scale ÷ crop), orientation applied and `kCGImageSourceShouldCacheImmediately = true`, on background tasks, at most three at a time, nearest cards first. Full-resolution images are never decoded for display.
- **Cache**: `ImageStore`, keyed by `(assetID, size)` with sizes bucketed to powers of two (64…8192 px), so each photo has only a handful of decodes. Any cached decode at least as large as the request is reused. It's an LRU bounded by about a tenth of physical memory (256 MB to 1.5 GB). Photos far off screen release their bitmap, so the cache is the only thing holding them.
- **Cropping** happens at display time with `CGImage.cropping(to:)` on the decoded image, which shares its pixels, so reframing and resizing never re-decode unless more pixels are needed.
- **Lazy base64**: an asset's base64 is decoded into `Data` only inside the decode task and released right after.

### 10.6 Culling and hit testing

- **SpatialGrid**: a uniform grid (512 pt cells) over each card's *rotated* bounding box, updated on every change. It's simpler than an R-tree and just as fast at these sizes. Huge cards go in an overflow list, and very large queries scan occupied cells instead of empty ones.
- **Visible set** = query(viewport rect expanded by 25%). Only visible cards get content bitmaps. Card chrome layers exist for every card: Core Animation skips off-screen layers when compositing, and 500 cards of chrome is cheap. Layer pooling was kept in reserve for M6; the M6 budgets (§11) pass without it, so it isn't built. Mid-gesture, only cards that just came into view join the render queue, which draws for 1.5 ms of a moving frame (5 ms at rest) and is re-sorted, nearest first, once the camera settles.
- Strings are visible if their Bézier bounding box intersects the viewport.
- **Hit testing**: grid point query, then exact test in card-local (unrotated) space, topmost by `z`. For strings: a coarse bounding-box check, then distance to a pre-flattened polyline (16 segments), within 6 pt screen distance.

### 10.7 String geometry

```swift
/// Cubic Bézier that sags like thread under gravity.
func stringPath(from a: CGPoint, to b: CGPoint, sag: CGFloat, fanOffset: CGFloat = 0) -> CGPath {
    let d = hypot(b.x - a.x, b.y - a.y)
    let droop = min(d * 0.18, 140) * (0.25 + sag)       // longer strings droop more, capped
    let normal = CGVector(dx: -(b.y - a.y) / max(d, 1), dy: (b.x - a.x) / max(d, 1))
    let gravityY = droop + fanOffset * 18                // world y grows downward
    let c1 = CGPoint(x: a.x + (b.x - a.x) / 3 + normal.dx * fanOffset * 12,
                     y: a.y + (b.y - a.y) / 3 + gravityY)
    let c2 = CGPoint(x: a.x + 2 * (b.x - a.x) / 3 + normal.dx * fanOffset * 12,
                     y: a.y + 2 * (b.y - a.y) / 3 + gravityY)
    let p = CGMutablePath()
    p.move(to: a)
    p.addCurve(to: b, control1: c1, control2: c2)
    return p
}
```

- **Gradient along the string**: a `CAGradientLayer` framed to the curve's box, with axis start = `a` and end = `b`, masked by a `CAShapeLayer` whose bounds origin is the box origin, so the mask path stays in world coordinates.
- **Thread texture**: a second, thinner stroke dashed at about [½, 1] × thickness, 25% white, nudged up a fraction of a point. It reads as twisted fibers up close and is hidden below 60%.
- **Shadow**: a separate layer whose `shadowPath` is the stroked curve (dashed first for dashed strings), offset (0, 3), blur 4, 35%. It's only computed at full detail, so dragging cards at lower zoom never strokes paths.
- **Knots, arrowheads and label**: a knot over each pin in the end's color; arrowheads sit just clear of the pin, along the curve's last segment; the label is a capsule at `B(0.5)` with its text drawn per zoom tier like card text.
- **Levels of detail** follow §10.4: gradient, texture, shadow and label at full; a solid stroke when reduced; a 1-screen-point hairline at minimal. Dimmed strings (Focus/Trace) turn solid at 28% alpha instead of using layer opacity, which would force an offscreen pass per string.
- **Hit testing** uses the 16-segment polyline kept from the last layout (§10.6); a label also counts as the string.
- **Slack dragging**: the middle of the curve sits `0.75 × droop` below the chord, so dragging by `dy` changes sag by `dy / (0.75 × droopCap)` and the middle follows the pointer exactly.
- **During drag**, only the strings attached to dragged cards recompute their path (an adjacency map from card ID to string IDs, O(degree)).
- **Springs**: the live connect string's loose end and the "pull taut" overshoot are stepped by hand on a display link (a damped spring, fixed 1/240 s substeps), because they re-route the curve every frame. Draw-in, snapping away and the pin pulse are plain Core Animation. The Trace pulse is driven by the same frame ticker: each frame it cuts the 60 pt piece of the joined path where the glow is and draws it as a soft wide stroke under a bright core. It only runs while Trace is on. (A test checks where the glow is at a given time. CI screen captures never showed the pulse in any form, keyframe or ticker-driven, even though the app's own state was right, so it still needs checking on a real Mac.)
- **Bounds**: every shape layer gets bounds around what it draws, with the bounds origin at the box's corner so paths stay in world coordinates.
- **Reduce Motion** is read in one place; debug builds launched for a snapshot scenario ignore it, because the CI Mac has it on.

### 10.8 Input handling

A **tool state machine** in the canvas:

```
idle ──mouseDown(card)──▶ pressingCard ──drag>3pt──▶ draggingCards ──mouseUp──▶ idle (commit MoveCards)
 │                            └──mouseUp──▶ idle (select)
 ├─mouseDown(pin, or card with C)──▶ connecting ──mouseUp(on card)──▶ idle (commit insertStrings)
 │                                       └──mouseUp(empty) / Esc──▶ idle (string retracts)
 ├─mouseDown(string)──▶ pressingString ──drag>3pt──▶ adjustingSag ──mouseUp──▶ idle (commit updateStrings)
 ├─mouseDown(empty)──▶ marquee ──mouseUp──▶ idle (select)
 ├─space down──▶ panReady ──drag──▶ panning
 └─doubleClick(empty)──▶ creatingText ──▶ editingText
```

Trackpad `scrollWheel` is pan, `magnify(with:)` is zoom and `smartMagnify` is zoom-to-card. During `draggingCards`, positions update layer `position` directly (no model writes). The `MoveCards` command is applied **once** on mouseUp, which makes it one undo step and one model change.

---

## 11. Performance budgets

Reference hardware: base M1 MacBook Air. Targets must also hold on a 120 Hz ProMotion display.

| Scenario | Budget |
|---|---|
| Pan or zoom, 500 cards (200 images, 150 web) | **120 fps**, main thread < 4 ms per frame |
| Pan or zoom, 3,000 cards | ≥ 60 fps (LOD + culling) |
| Drag 50 selected cards with 200 attached strings | ≥ 120 fps |
| Cold launch to empty board | < 400 ms |
| Open a 50 MB board (300 cards) | First frame < 800 ms, full-res visible images < 1.5 s |
| Save a 50 MB board (with cached base64) | < 300 ms, off the main thread |
| Memory, 500-card board at rest | < 450 MB |
| Idle CPU / network | **0% / 0 bytes** |
| Link preview, typical site | Title < 400 ms, hero < 1.5 s |

Instruments templates are checked into `Tools/Instruments/` (Time Profiler, Core Animation FPS, Allocations, Hangs). CI runs `XCTMetric` performance tests (§15) with regression thresholds.

**As built (M6).** CI checks the budgets on every push, on a GitHub macOS 15 arm64 runner (a virtual Mac, slower than an M1 Air), in a release build. A Swift Testing suite (`PerformanceTests`, `CodecPerformanceTests`, run with `EB_PERF=1`) drives a real canvas in an offscreen window and measures **main-thread time per frame**: what the app controls. Core Animation's render server and the display aren't measured, so frame rate itself still needs Instruments on a real Mac. Results from the run that closed M6:

| Scenario | Budget | Measured in CI |
|---|---|---|
| Pan, 500 cards (200 photos, 150 web), p95 frame | < 4 ms | 0.1–0.5 ms |
| Zoom, 500 cards, p95 frame | < 4 ms | 2.2–3.3 ms |
| Pan or zoom, 3,000 cards, p95 frame (whole board in view, 30%, zoom sweep) | < 16.7 ms | 1.8–3.7 ms |
| Drag 50 cards with 200 strings, p95 frame | < 8.3 ms (one 120 Hz frame) | 7.3 ms |
| Open a 52 MB, 300-card board: decode and validate | < 500 ms | 60–115 ms |
| Open that board: first frame | < 800 ms | 183 ms |
| Open that board: visible photos decoded | < 1.5 s | 327 ms |
| Save a 50 MB board | < 300 ms | 42–65 ms |
| Memory, 500-card board at rest | < 450 MB | 269 MB |
| Work scheduled at rest (display links, physics, pulses, fetches) | none | none |
| Launch to first board frame (Debug build, snapshot workflow) | < 400 ms | see the snapshot run summary |

Dragging is the tightest: re-routing 200 strings every frame. It's the first place to look if a real Mac drops frames.

The link-preview budget needs the network and isn't measured in CI. Saving got its speed from writing image data straight into the JSON (it's plain base64, so it needs no escaping) instead of passing megabytes of text through the encoder.

---

## 12. Xcode project setup

### 12.1 Targets

| Target | Type | Purpose |
|---|---|---|
| `EvidenceBoard` | macOS App | The app |
| `BoardKit` | Swift Package (local) | Model, codec, migrations, graph queries. No UI, so it's fully unit-testable |
| `CanvasKit` | Swift Package (local) | Canvas engine (AppKit + CA) |
| `LinkPreviewKit` | Swift Package (local) | Metadata pipeline, palette extraction |
| `EvidenceBoardPreview` | Quick Look Preview Extension (data-based) | Space in Finder shows the whole board as a picture |
| `EvidenceBoardThumbnail` | Thumbnail Extension | Finder icon = board snapshot |

*As built (M6):* both extensions live in `QuickLook/` and draw with `BoardRenderer` (CanvasKit), which renders a board without a window: background, cards with shadows, text, photos and link previews, strings and pins, with placeholder bars where text would be too small to read. They read only the file, never the network, and are sandboxed. Their modules build in the Swift 5 language mode, since Quick Look's completion handlers predate Swift concurrency.
| `EvidenceBoardTests` / `…UITests` | Test bundles | §15 |

There are **no third-party dependencies**. The HTML `<head>` parser is a small hand-written tokenizer (meta, link, title and `application/ld+json` script blocks only), about 300 lines in `LinkPreviewKit`.

### 12.2 Folder structure

```
EvidenceBoard.xcodeproj
EvidenceBoard/
├── App/
│   ├── EvidenceBoardApp.swift
│   ├── BoardDocument.swift
│   ├── BoardCommands.swift          # menu bar: File, Edit, Insert, Board, View
│   └── SettingsView.swift
├── Window/
│   ├── BoardWindow.swift            # canvas + HUD composition
│   ├── Toolbar/                     # ToolPicker, SearchField, ThemeMenu
│   ├── Inspector/                   # TextInspector, ImageInspector, WebInspector, StringInspector
│   ├── Minimap/
│   └── ZoomHUD/
├── Cards/                           # SwiftUI designs, rendered to bitmaps by CanvasKit
│   ├── TextCardView.swift
│   ├── ImageCardView.swift
│   ├── WebCard/
│   │   ├── WebCardView.swift        # variant switch
│   │   ├── HeroLayout.swift  PortraitLayout.swift  MediaLayout.swift
│   │   ├── SocialLayout.swift  ArticleLayout.swift  CompactLayout.swift
│   │   └── SkeletonShimmer.swift
│   └── Pin.swift
├── Theme/
│   ├── Theme.swift                  # token struct
│   ├── Themes+Noir.swift  Themes+Cork.swift  Themes+Blueprint.swift  Themes+Daylight.swift
│   └── Materials.swift              # glass helpers with #available(macOS 26) Liquid Glass
├── Peek/
│   └── PeekPopover.swift            # lazy WKWebView
├── Resources/
│   ├── Assets.xcassets   AppIcon.icon   Localizable.xcstrings
│   └── Textures/                    # (none: textures are procedural)
└── Supporting/
    ├── Info.plist
    └── EvidenceBoard.entitlements
Packages/
├── BoardKit/      Sources/BoardKit/{Model, Codec, Migrations, Graph, Commands}
├── CanvasKit/     Sources/CanvasKit/{Canvas, Camera, Nodes, Text, Editing, Interaction, Spatial, ImagePipeline}
└── LinkPreviewKit/Sources/LinkPreviewKit/{Fetch, HeadParser, Merge, Palette, Cache}
Tools/Instruments/
docs/
```

### 12.3 Build settings

| Setting | Value |
|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | 15.0 |
| `SWIFT_VERSION` | 6 |
| `SWIFT_STRICT_CONCURRENCY` | complete |
| `ENABLE_HARDENED_RUNTIME` | YES |
| Sandbox | On, through `Config/EvidenceBoard.entitlements` |
| `SWIFT_OPTIMIZATION_LEVEL` (Release) | `-O`, plus whole-module optimization |
| `DEAD_CODE_STRIPPING` | YES |
| Architectures | Apple silicon + Intel (universal) |

### 12.4 Info.plist (document types)

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>            <string>Evidence Board</string>
    <key>CFBundleTypeRole</key>            <string>Editor</string>
    <key>LSHandlerRank</key>               <string>Owner</string>
    <key>LSItemContentTypes</key>          <array><string>com.evidenceboard.board</string></array>
  </dict>
  <dict>
    <key>CFBundleTypeName</key>            <string>JSON</string>
    <key>CFBundleTypeRole</key>            <string>Viewer</string>
    <key>LSHandlerRank</key>               <string>Alternate</string>
    <key>LSItemContentTypes</key>          <array><string>public.json</string></array>
  </dict>
</array>
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>            <string>com.evidenceboard.board</string>
    <key>UTTypeDescription</key>           <string>Evidence Board</string>
    <key>UTTypeConformsTo</key>            <array><string>public.json</string><string>public.data</string><string>public.content</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key> <array><string>evboard</string></array>
      <key>public.mime-type</key>          <array><string>application/vnd.evidenceboard+json</string></array>
    </dict>
  </dict>
</array>
```

### 12.5 Entitlements

```xml
<key>com.apple.security.app-sandbox</key>                  <true/>
<key>com.apple.security.network.client</key>               <true/>   <!-- link previews only -->
<key>com.apple.security.files.user-selected.read-write</key><true/>   <!-- open/save panels, drag-in -->
<key>com.apple.security.files.downloads.read-only</key>    <true/>   <!-- optional: dragging from Downloads -->
```

---

## 13. Security & privacy

- **No JavaScript execution** when generating previews. HTML is tokenized as text and only the `<head>` is read. Responses over 512 KB are cut off.
- **Only `http` and `https` URLs** become Web cards. `file:`, `javascript:`, `data:` and custom schemes are rejected (they're pasted as Text instead).
- **Image decoding** goes through ImageIO only, with a pixel-count limit of 100 MP, to guard against decompression bombs.
- **Opening a file is network-silent.** A shared board can't be used as a tracking beacon, because previews render from the embedded snapshot.
- **Peek** uses `WKWebsiteDataStore.nonPersistent()`, so there are no cookies, no shared login and no persistence.
- **Untrusted JSON** goes through bounded parsing. Files over 2 GB are rejected, and string lengths and card counts are capped (100k cards) to avoid memory exhaustion. *As built (M6):* text is capped at a million characters and titles, captions, labels and link fields at 10,000; 500k strings and 100k assets; a photo crop that isn't finite is dropped and one outside the photo is pulled back in; an impossible video duration is dropped. Whatever loads is guaranteed to save, and saving then reloading changes nothing; a seeded mutation test and a 60-second libFuzzer run in CI check exactly that (§15).
- **No analytics** and no network calls other than link previews the user explicitly requested.

---

## 14. Accessibility

- The canvas exposes an **accessibility tree**. Each card is an `NSAccessibilityElement` with role `group`, a label (*"Text card: Ferry left 11 minutes early"*, *"Web card: Harbor authority releases night logs, example.com"*) and custom actions (Open, Connect…, Delete, Lock).
- Each string is exposed as *"String from ⟨card A⟩ to ⟨card B⟩, labelled ⟨label⟩"*. Every card has a **Connections** rotor listing its strings, so you can follow the dots with VoiceOver.
- **Full keyboard operation**: Tab / ⇧Tab cycles cards in reading order (top-left to bottom-right). ⌥ + arrow keys move focus spatially to the nearest card in that direction. ⌘K connects the two most recently focused cards.
- **Contrast**: all text meets WCAG AA (4.5:1). The link-card scrim guarantees this over any image (§7.1).
- **Reduce Motion**, **Reduce Transparency** (glass becomes solid theme colors) and **Increase Contrast** (card strokes at 40%, strings +1 pt) are all honored.
- String colors are never the only signal. Labels and dash styles provide redundant encoding.

**As built (M6).** The canvas is a *layout area* whose children are the cards, in reading order, then the strings. A card says its kind and content ("Text card: Ferry left 11 minutes early, amber, locked, 2 connections"; "Web card: Harbor authority releases night logs, example.com"), and its actions are Edit (or Edit Caption, or Open in Browser and Peek), Connect to the card focused before it, Focus on Connections, Lock or Unlock, and Delete. A string says "String from ⟨A⟩ to ⟨B⟩, labelled ⟨label⟩", plus its arrow and dash style, with actions to go to either end, edit the label or delete it. The Connections rotor walks a card's strings. Tab, ⇧Tab, ⌥ + arrows (to the nearest card within about 70° of the direction) and ⌘K work as above, with each move announced. Increase Contrast draws card edges at 40% and strings a point thicker and makes translucent fills opaque; Reduce Transparency turns glass panels and translucent cards solid. A test checks every theme's card text, typewriter text, captions and string labels against 4.5:1, over both ends of each gradient and of the board behind translucent fills.

---

## 15. Testing strategy

| Layer | What | How |
|---|---|---|
| **BoardKit** | Codec round-trip, migrations, validation, unknown-field preservation, graph queries (focus N hops, shortest-path trace) | Swift Testing (`@Test`), golden JSON fixtures in `Tests/Fixtures/` |
| **Commands / undo** | Every command's inverse restores an identical board | Property-based tests: random command sequences, then undo all, then compare to the original |
| **LinkPreviewKit** | Head parser against 62 saved page heads modeled on real sites; merger priority; variants; palette roles; cache | Fixtures with expectations in a leading comment, no live network in CI |
| **CanvasKit** | Camera math, hit testing and resizing on rotated cards, spatial grid against brute force, text measuring and rendering, string path bounds | Unit tests |
| **Rendering** | Card visuals per theme and variant | Web card layouts for all 62 fixtures at four widths are checked for overlaps, overflow and line limits. Screenshots of every variant come from the snapshot workflow |
| **Performance** | Pan/zoom FPS on a synthetic 500 / 3,000-card board, open/save timings | `XCTOSSignpostMetric`, `XCTMemoryMetric`, `XCTClockMetric` with baselines. *As built:* a release-build Swift Testing suite measures main-thread frame time, open/save, memory and idle work against the §11 budgets, and CI prints a budget table |
| **UI** | Create, paste, connect, save, reopen flows | XCUITest |
| **Fuzzing** | Board loader against malformed and huge JSON | libFuzzer harness on `BoardCodec.decode` (`Tools/Fuzz`, 60 s per CI run, about 2,000 inputs a second), plus a seeded test of 5,500 byte-level and structural mutations that runs with the unit tests |
| **Accessibility** | VoiceOver labels, actions and rotor; keyboard focus; WCAG AA contrast of every theme | Unit tests on the accessibility tree and key handling; a contrast test over all four themes, also with Increase Contrast |

---

## 16. Roadmap

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 — Skeleton** | Xcode project, packages, `DocumentGroup`, JSON codec v1, empty Noir canvas with camera | Opens and saves an empty `.evboard`. Pan and zoom at 120 fps |
| **M1 — Text cards** | Create, edit, move, resize and delete text cards. Undo. Snapshot-at-rest rendering | 500 text cards at 120 fps |
| **M2 — Image cards** | Drop and paste images, asset table, image pipeline, frame styles, captions, crop | 200 photos, memory under budget |
| **M3 — Strings** | Pins, connect gesture, sag geometry, gradients, labels, Focus and Trace modes | "Connect the dots" feels physical. Trace works on 1,000-edge graphs in < 5 ms |
| **M4 — Web cards** | Metadata pipeline, palette, all 7 layout variants, skeletons, snapshots, Peek | 60-site fixture suite renders with no layout bugs |
| **M5 — Design polish** | All 4 themes, motion specs, Liquid Glass, app icon, minimap, search | Design review sign-off |
| **M6 — Hardening** | LOD, culling, performance budgets, accessibility, fuzzing, Quick Look extensions | All §11 budgets green in CI *(done; see the table in §11)* |
| **1.0** | Notarized, Developer ID and Mac App Store builds | — |

**Post‑1.0 ideas** (they keep the three-card-type rule): the `.evboardpkg` package format for huge boards, iCloud Drive sync of board files, an iPad companion app (shared `BoardKit` + `LinkPreviewKit`), a timeline arrangement (auto-layout cards by `publishedAt`) and Shortcuts / App Intents ("Add link to board").

---

## Appendix A: keyboard shortcuts

| Shortcut | Action |
|---|---|
| V / C / H | Select / Connect / Hand tool |
| Double-click canvas, or T | New text card (at the pointer) |
| ⌘⇧T | Insert ▸ Text Card |
| Double-click card, or ↩ | Edit text |
| ⌘↩ or Esc (while editing) | Finish editing |
| ⌘L | Insert link… |
| ⌘⇧I | Insert image… |
| ⌘V / ⌘⇧V | Paste / paste as plain text |
| ⌘D | Duplicate selection |
| ⌫ | Delete selection |
| ⌘K | Connect two selected cards |
| F | Focus mode (press again to widen by one hop) |
| ⌘T | Trace path between two selected cards |
| Space | Peek web card (live view) |
| ⌘↩ | Open web card in browser |
| ⌘R / ⇧⌘R | Refresh link preview / all previews |
| ⌘F | Search board |
| ↩ or ⌘G / ⇧⌘G | Next / previous search match |
| ⌘0 / ⌘1 / ⌘2 | Zoom to fit / 100% / selection |
| ⌘+ / ⌘− | Zoom in / out |
| ⌘] / ⌘[ | Bring forward / send backward |
| ⌘⇧] / ⌘⇧[ | Bring to front / send to back |
| ⌘⌥L | Lock or unlock |
| ⌥⌘I | Toggle inspector |
| ⌥⌘T | Cycle theme |
| Arrow / ⇧ + arrow | Nudge 1 pt / 10 pt |
| Esc | Deselect, exit tool, or exit Focus/Trace |
