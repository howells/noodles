# Design Direction: Noodles Landing Page

## Aesthetic Direction
- **Tone:** Playful, physical, toy-like — an interactive canvas, not a web page
- **Memorable element:** Three white cards springing from the void at jaunty angles, draggable with spring physics, over a living dot-field that breathes and a green cursor trail
- **Design mode:** Marketing — single-page app showcase
- **UI chrome:** None — no header, footer, or navigation. Pure immersive experience.

## Typography
- **Display:** Space Grotesk (700) — "Noodles" title card, geometric with personality
- **Body:** DM Sans (400/500) — description card text, clean and friendly
- **Mono:** Not used
- **Source:** Google Fonts, self-hosted via `next/font/google`

## Color Palette

| Role | Value | Usage |
|------|-------|-------|
| Background | `#0a0a0a` | Page canvas — near-black void |
| Dot grid | `#2a2a2a` | Background dot field — subtle grey |
| Card surface | `#fafaf9` | Physical cards — warm off-white |
| Card text | `#1a1a1a` | Headings/body on cards |
| Card text secondary | `#6b6b6b` | Subtitle/description text |
| Green accent | `#22c55e` | Cursor trail dots — electric green |
| Green glow | `#22c55e40` | Faint bloom around trail dots |
| Card shadow | `rgba(0,0,0,0.3)` | Layered shadow beneath cards |

Three materials: the **void** (dark dot grid), the **objects** (white cards), the **trail** (green life).

## Spacing
- Base unit: 8px
- Card internal padding: 32px
- Card positioning: Physics-based, not grid-based
- No traditional section rhythm — this is a canvas

## Motion

This page is *about* motion. Animation is the feature.

### Sequence

1. **Dot grid reveal** (~1.5s)
   - Grey dots fade in concentrically from viewport center
   - Each dot's delay = `distance_from_center * multiplier`
   - Opacity spring: 0 → 1 with gentle overshoot
   - Dots are ~8px diameter, spaced ~32px apart in a uniform grid

2. **Card entrance** (begins after dot grid settles, ~0.6s per card, staggered ~0.15s apart)
   - Cards spring up from below viewport bottom
   - `translateY(100vh + 200px)` → resting position
   - Each card has a different resting rotation:
     - Card 1 ("Noodles"): `rotate(-6deg)`, slightly left of center
     - Card 2 ("Description"): `rotate(3deg)`, center
     - Card 3 ("Video"): `rotate(-2deg)`, slightly right of center
   - Spring config: `{ stiffness: 200, damping: 18 }` — bouncy but controlled

3. **Card drag** (continuous, user-initiated)
   - Cards are draggable via `motion.div` with `drag` prop
   - `dragConstraints` = small radius around resting position
   - `dragElastic={0.5}` — resistance beyond constraints
   - On release, spring back to resting position + original rotation
   - Spring config: `{ stiffness: 300, damping: 20 }`

4. **Video modal** (on click of video card)
   - Card scales and translates to center viewport
   - Rotation animates to `0deg` (stable viewing position)
   - Card expands to fill ~80% viewport width (max 960px)
   - Background overlay fades in: `rgba(0,0,0,0.8)` + `backdrop-blur(12px)`
   - Video auto-plays once transition completes
   - Dismiss: click overlay or press Escape
   - On dismiss: card springs back to resting position + rotation
   - Use `layoutId` for shared layout animation between card and modal

5. **Cursor trail** (continuous, desktop only)
   - Track mouse position via `onMouseMove` on the page container
   - Render trail of ~12 green dots following the cursor
   - Each dot: 8px diameter, same size as background dots
   - Dots have decaying opacity (newest = 1.0, oldest = 0.1)
   - Slight green glow (`box-shadow: 0 0 8px var(--green-accent)`)
   - Hide on touch devices — no cursor trail on mobile
   - Use `@media (hover: hover) and (pointer: fine)` to gate

### Reduced Motion

- Honor `prefers-reduced-motion`:
  - Dots appear immediately (no stagger)
  - Cards appear at resting positions (no spring entrance)
  - Drag still works (springs are user-initiated, acceptable)
  - Video modal uses simple opacity fade instead of layout animation
  - Cursor trail still works (follows user intent)

### Session Skip

- Store `sessionStorage.introSeen` after first load
- On repeat visits: skip dot grid stagger, cards appear at rest

## Layout

### Desktop (≥768px)

```
┌─────────────────────────────────────────────────┐
│ · · · · · · · · · · · · · · · · · · · · · · · · │
│ · · · · · · · · · · · · · · · · · · · · · · · · │
│ · · · · ┌──────────────┐ · · · · · · · · · · · │
│ · · · · │  Noodles      │╲ · · · · · · · · · · │
│ · · ┌───│──────────────┐│ · · · · · · · · · · · │
│ · · │ De│v server mgr  ││ · · · · · · · · · · · │
│ · · │ fo│r macOS.      ││────────────┐ · · · · · │
│ · · │ Ke│eps your local││ ▶ [video]  │ · · · · · │
│ · · │ se│rvers in line.││            │╲ · · · · │
│ · · └───│──────────────┘│            │ · · · · · │
│ · · · · └──────────────┘└────────────┘ · · · · · │
│ · · · · · · · · · · · · · · · · · · · · · · · · │
│ · · · ● ● ● · · · · · · · · · · · · · · · · · · │
└─────────────────────────────────────────────────┘

Cards are centered as a cluster, overlapping slightly.
Each rotated at its own angle.
Green cursor trail follows mouse.
```

### Mobile (<768px)

```
┌─────────────────────┐
│ · · · · · · · · · · │
│ · · · · · · · · · · │
│ · ┌───────────────┐ │
│ · │  Noodles       │ │
│ · └───────────────┘ │
│ · · · · · · · · · · │
│ · ┌───────────────┐ │
│ · │  Dev server    │ │
│ · │  manager for   │ │
│ · │  macOS         │ │
│ · └───────────────┘ │
│ · · · · · · · · · · │
│ · ┌───────────────┐ │
│ · │  ▶ [video]    │ │
│ · │               │ │
│ · └───────────────┘ │
│ · · · · · · · · · · │
└─────────────────────┘

Cards stacked vertically, less rotation (~2°).
Still spring entrance from bottom.
No cursor trail (touch devices).
Cards draggable with touch drag.
```

## Card Content

### Card 1: Title
- **Text:** "Noodles" in Space Grotesk 700, ~48px
- **Size:** ~240 × 120px
- **Style:** Clean, just the name. Maybe a subtle app icon above.

### Card 2: Description
- **Text:** Brief tagline in DM Sans 400, ~18px
  - "A tiny menu bar app that manages your Node.js dev servers. Start, stop, and monitor everything from one place."
- **Size:** ~320 × 180px
- **Style:** Readable body text on warm white card

### Card 3: Video
- **Content:** Embedded video showing the app in action
- **Size:** ~360 × 240px (16:10 ratio to match app)
- **State:** Paused with play icon overlay
- **On click:** Expands to modal, auto-plays

## Implementation Notes

### Dependencies
- `motion` — springs, drag, layout animations
- `motion-plus` — `<Cursor>` component for the green dot trail
- `next/font/google` — Space Grotesk + DM Sans
- Install motion-plus via: `"motion-plus": "https://api.motion.dev/registry?package=motion-plus&version=2.0.0&token=547f9719bf0fd6b50c6e5014a3137fd442d8351128a6b222f8c5145f15ab5efa"`

### Technical Approach
- **Dot grid:** Generate dots with `useMemo` based on viewport size. Each dot is a `motion.div` with `initial={{ opacity: 0 }}` and staggered `animate`.
- **Cursor trail:** Use Motion+ `<Cursor>` component with a custom green dot render, configured for trail effect.
- **Card drag:** `motion.div` with `drag`, `dragConstraints`, `dragElastic`, `onDragEnd` to spring back.
- **Video modal:** `AnimatePresence` + `layoutId` for shared element transition. `<video>` element with `ref.current.play()` on modal open.
- **Responsive:** Cards switch from scattered cluster to vertical stack below 768px.
- **Performance:** All animations use `transform` and `opacity` only (compositor thread). Dot grid uses `will-change: opacity` during entrance, removed after.

### File Structure
```
site/src/app/page.tsx          — main page, orchestrates all sections
site/src/components/DotGrid.tsx — background dot field with concentric reveal
site/src/components/Cards.tsx   — three draggable cards with spring physics
site/src/components/VideoModal.tsx — expandable video card + overlay
site/src/components/CursorTrail.tsx — green dot trail following mouse
```

## Anti-Patterns to Avoid
- No scroll-triggered animations — everything happens on load or interaction
- No parallax effects
- No cookie-cutter layout — this explicitly breaks every convention
- No header/footer/nav — the page IS the experience
- No auto-playing video (plays only when user opens modal)
- No purple gradients, no AI slop
- Cards should feel physical, not digital — shadows, slight card texture maybe
