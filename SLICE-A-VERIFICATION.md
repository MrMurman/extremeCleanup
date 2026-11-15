---
status: draft
date: 2026-11-13
genre: verification
scope: task
feature: Extreme Cleanup — blower crack and director beats (Slices A, A2 and B)
---

# Slices A, A2 and B — Extreme Cleanup verification

## Manual Test Checklist

### 1. Basic Crack Timing
- [ ] Launch app, select leaf blower (key `3`)
- [ ] Click and hold at screen center, drag ~100pt right to aim
- [ ] **Without moving the aim**, keep blowing for 3+ seconds
- [ ] **Expected:** Crack appears ~120pt ahead of nozzle after ~3s with crack sound
- [ ] **Expected:** Crack grows to big crack after ~6s total (another ~3s)
- [ ] **Expected:** No hole opens — blower stops at big crack stage

### 2. Aim Reset Behavior
- [ ] Start blowing, hold aim for 2 seconds
- [ ] Turn the cone > 10° away
- [ ] **Expected:** Timer resets, no crack yet
- [ ] Hold new aim for 3+ seconds
- [ ] **Expected:** New crack appears at new aim position

### 3. Sweeping Leaves Doesn't Crack
- [ ] Start blowing
- [ ] Continuously sweep back and forth (changing aim)
- [ ] Do this for 10+ seconds
- [ ] **Expected:** No cracks appear (aim never held long enough)

### 4. Visual Quality
- [ ] Observe crack appearance
  - [ ] Crack: ~70pt reach, 6-9 rays
  - [ ] Big crack: ~230pt reach, 11-15 rays, dramatic spread
  - [ ] Growth animates over ~0.4s (crack) or ~1.1s (big crack)
  - [ ] Not instant — spreads outward visibly

### 5. Glow Effect
- [ ] Observe warm glow through crack lines
  - [ ] Orange/red layered glow visible
  - [ ] Pulses (fades 0.55 ↔ 1.0 alpha)
  - [ ] Big crack glow is brighter than regular crack
  - [ ] Glow uses additive blend mode

### 6. Sound
- [ ] Listen for crack sound when crack appears
- [ ] Volume ~0.6 for first crack, 1.0 for big crack
- [ ] Screen shake on big crack (strength 6)

### 7. Bounds Checking
- [ ] Try to crack near screen edge
- [ ] **Expected:** No crack if impact point is outside frame inset by 10pt
- [ ] Try to crack where glass is already shattered (hole exists)
- [ ] **Expected:** No crack lands on a hole

### 8. Integration with Other Systems
- [ ] Create a blower crack
- [ ] Switch to broom and sweep
- [ ] **Expected:** Crack disappears with everything else
- [ ] Create cracks while leaves are falling
- [ ] **Expected:** Leaves keep blowing/falling normally

### 9. Performance
- [ ] Run app for 30 seconds with blower active and cracks growing
- [ ] Monitor frame rate (app shows FPS in debug)
- [ ] **Expected:** No sustained hitches > 25ms
- [ ] **Expected:** Smooth animation during crack growth

## Implementation Status

✅ **Code complete** (2026-11-09):
- Timer mechanics (`heldAim`, `crackDwell`, `aimTolerance`)
- Crack detection at `airReach` (120pt) ahead of nozzle
- Damage cap at 2 (crack → big crack, never hole)
- Dramatic blower cracks (reach 70/230, rays 6-9/11-15)
- Growth animation over ~0.4s / ~1.1s
- Warm pulsing glow (orange/red layers, additive blend)
- Sound trigger at crack appearance
- Integration with update loop (`pressAir` + `growCracks`)
- Broom clears cracks as before

✅ **Builds successfully** — `./scripts/bundle.sh` passes

⏳ **Awaiting owner live check** — manual verification per checklist above

## Notes

- Slice A originally had no headless test; `--demo-blower` now covers the active fracture timing and no-hole condition
- Verification follows the pattern from leaf feature (owner live check + render inspection)
- Frame time budget from leaf feature: no hitch > 25ms
- Earlier crack textures and `thin-fissure` are preserved in the A2 archive

## Slice A2 — texture crack experiments (archived 2026-11-12)

These comparison styles were superseded by the cumulative fracture style below. Their code and art
are preserved in `Archive/blower-crack-iterations/` and are no longer compiled or bundled.

### What changed

- `BlowerCrackStyle` (`code`, `texture`, `texturePlain`) and the `BlowerCrackVisual` protocol. The
  scene owns timing (`crackGrowth`, `pressureReach`); the visual owns the drawing.
- `DrawnBlowerCrack` — Slice A extracted unchanged; `TextureBlowerCrack` — the A2 look.
- One texture per site (`lvl1-impact`, `lvl2-impact`, `lvl3-impact`), stable across both stages so the
  big crack grows out of the small one; 460 pt, rotated/mirrored, additive.
- Growth: the whole feathered crack scales from 70/230 (≈30 %) to 230/230 (100 %) over 0.4 s /
  1.1 s. There is no circular crop mask: the texture's own edge fades, so rays keep their natural ends.
- Glow: pre-blurred 512 px copies, crimson/magenta glass, red-orange heat, gold and a white-hot
  core, pulsing; the crack itself is layered crimson → gold → white-hot. Every light layer is a
  copy of the crack texture, never a radial disc, so light only shows through cracks; a dark blurred
  shadow keeps them visible on light wallpapers.
- Sparks: one burst when the crack appears, a low emission while it grows; the colour runs gold →
  crimson over the particle lifetime.
- `BlowerCrackArt.prepare()` loads and blurs once at scene setup; a near-invisible prewarm pass draws
  every variant once, so the first crack does not pay for texture upload or the crop pipeline.
- `worstFrame` reports the longest single frame (a one-second average hides one hitch).
- `--demo-blower <dir>` scripted check; `--crack-style code|texture|texturePlain` and `T` switch styles
  at runtime. Cracks already drawn keep their style; new ones use the selected one.
- README credits the crack art and `scripts/clean-crack-art.py`.

### Headless results (2026-11-10, this Mac)

| style | crack at 3 s | big crack at 6 s | one site | no hole | worst frame |
|---|---|---|---|---|---|
| `code` | PASS | PASS | PASS | PASS | 9.4 ms |
| `texture` | PASS | PASS | PASS | PASS | 14.6 ms |

- The `texture` run was after the per-site variant change, the banner-palette pass and the
  no-circle scaling change; the frame budget is 25 ms.
- Captures: `.build/a2-demo-code/5-final-scene.png` (code baseline),
  `.build/final-demo/5-final-scene.png` (big crack), `.build/final-demo/6-crack-stage-scene.png`
  (first crack), `.build/ember-demo/5-final-scene.png` (the separate ember experiment; gitignored,
  with a screen capture next to each).
- `thin-fissure` is a single line, not a radial impact; it is archived with these experiments.

## Slice A2 — final fracture style (2026-11-12)

**Selected by the owner as the only leaf-blower crack style.** `FractureBlowerCrack` uses the
full-resolution cumulative art: a stable level 1 core, extending outer fissures, then level 2 and
level 3 additions with selective red-orange light and pulse. The scene retains the 0.4 s / 1.1 s
growth windows and the existing crack timing.

- Removed `BlowerCrackStyle`, the `T` style switcher and `--crack-style`; every blower crack uses
  `FractureBlowerCrack` directly.
- `scripts/build-fracture-crack-art.py` prepares the active textures in `Support/assets/`.
- Earlier code-drawn, scaled-texture, plain-texture and ember iterations live in
  `Archive/blower-crack-iterations/`; they are outside the build and app bundle.

### Final scripted results (2026-11-12, this Mac)

`./scripts/bundle.sh` passed and produced the universal app. `--demo-blower` passed every check:
no crack before 3 s, crack after 3 s, big crack after 6 s, exactly one site, no hole, and a worst
frame of 14.6 ms against the 25 ms budget. The final captures are
`.build/final-fracture-demo/5-final-scene.png` and `6-crack-stage-scene.png`. No archived impact or
ember assets are present in the app bundle. **2026-11-13:** after the shared-shader prewarm described under
Slice B, the same demo reports 9.3 ms.

### Manual checklist (owner)

Confirmed by the owner on 2026-11-13.

- [x] Start the app, pick the blower, hold the aim for 3 s → a small fracture appears; hold for
      6 s → the cumulative big fracture grows out of it.
- [x] Check the glow and sparks on both a dark and a light wallpaper.
- [x] Both leaf styles: the crack uses the same fracture look.
- [x] Confirm there is no hole when blowing continuously on a clean spot.

### Out of scope (owner decision)

- The blower can still open a hole when its hit **merges two already-damaged sites** whose combined
  damage is ≥ 3. That is the planned later "blower breaks glass" feature, not A2; the demo holds on a
  clean spot, so it does not exercise it.

## Slice B — Director beats (2026-11-13)

Complete based on scripted verification. On 2026-11-15 the owner confirmed that Director mode is operated by agents for filming, removed the owner live-check gate, and requested the Slice B commit. Recording is the next focus.

### Choreography additions
- `tool`: `"blower"` (also `"leaf blower"` / `"leafblower"`) selects the leaf blower.
- `blow`: a `path` of `[x, y, hold]` / `{"icon": …, "hold": …}` stops and `for` seconds. The first stop is the
  nozzle (press), later stops are the drag/aim path; the air lands ahead of the nozzle as it does for a mouse.
  At least two stops are required.
- `gust`: `direction` -1/1, `strength` 0…1, optional `for` (default 3 s). Starts a gust immediately; leaves
  must already be on (the blower tool starts autumn).
- `belt`: `show` true/false and optional `for` (default 0.4 s). A top-level `belt` sets the opening state, so a
  take can start with the belt hidden.
- A top-level `crackDwell` overrides the blower's dwell for the take.
- Validation rejects a missing or out-of-range field before the take.

### Scripted results

`scripts/bundle.sh` passed. The new `--demo-director` plays a 4.6 s choreography (belt in, blower, gust, blow
with a 1.0 s dwell, belt out) and checks the scene and log:

- 13/13 PASS: belt starts hidden, dwell overridden, belt slides in, blower selected, autumn running, gust active,
  crack after the hold, belt slid out, frame under 25 ms, blow/gust/belt logged, validation rejects a gust
  without direction.
- Log: actions `belt, tool, gust, blow, belt, mark`; max drift 1.1 ms; worst frame 13.9 ms (budget 25 ms).

Regression runs after the change:
- `--demo-blower`: every check PASS; worst frame 9.3 ms. The shared-shader prewarm removed the 350–450 ms
  first-crack compile; the earlier cold run failed the 25 ms budget.
- `--demo-belt`: every check PASS; the empty-pocket range was corrected from pockets 2–7 to 3–7 (pocket 3 is
  the blower).
- `--demo-sweep`: clean in 2.62 s, Finder icons unchanged.
- `--demo-launcher`: 30/30 PASS, including the belt on the controls display.
- `--demo-hammer` / `--demo-minigun`: 97.2 / 97.0 fps during their 15 s / 30 s runs.
- `--demo-void`: holes, seam and creatures unchanged; 98.2 fps with seven holes open.

Captures and reports: `.build/slice-b-demo4/report.txt`,
`.build/slice-b-demo4/director-beats.log-*.json`, `.build/regress-blower10/report.txt`,
`.build/regress-belt2/report.txt`, `.build/regress-sweep/report.txt`,
`.build/regress-launcher/report.txt`.

### Shader prewarm (A2 follow-up)

`FractureBlowerCrack` now shares one `SKShader` and passes growth through a per-sprite `a_progress` attribute
instead of creating a shader object per layer. `prepare(in:)` caches the eight fracture/glow textures and renders
a real 460 pt fracture once at launch. This is what brings the scripted frame budget back under 25 ms.

### Out of scope

- The actual reel take, the Slice 0 recording account, music (D), typing/keyboard (C) and the cut (E).
- Blower holes from merged damage sites remain the planned later feature, not Slice B.
