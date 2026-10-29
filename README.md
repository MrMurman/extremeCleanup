# Extreme Cleanup

A desktop toy for macOS: take a hammer or a minigun to your screen, watch the glass crack, shatter and pile up at the
bottom. Built from scratch with AI as an homage to the 2000s classic *Desktop Destroyer*.

**It never touches your files.** The app takes a snapshot of your screen and wrecks the picture. Press
Esc and your real desktop is exactly as you left it.

> Work in progress — more tools and a proper release are on the way.

## Controls

The app opens with a small launcher: pick which displays to play on, which one shows the toolbelt, sound, and the
starting tool, then press **Start the cleanup**. Your choices are remembered.

| Key / mouse | Action |
|---|---|
| 1 / 2 | Pick a tool: hammer / minigun |
| Click | Hammer: one hit cracks, two widen the crack, three shatter the glass |
| Hold | Minigun: every round leaves a bullet hole; seven in one spot shatter it |
| C | Clean up: a broom sweeps the mess away and leaves a spotless desktop |
| Esc | Back to the launcher — your real desktop is untouched |
| ⌘Q | Quit |
| D | Debug overlay (frame rate, detected icons) |

## Permissions

- **Screen Recording** — to take the snapshot it smashes. Without it you get your wallpaper instead.
- **Automation → Finder** — read-only, to find where your desktop icons are.

## Build

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
scripts/bundle.sh                  # builds build/ExtremeCleanup.app
open build/ExtremeCleanup.app
```

## Credits

Inspired by *Desktop Destroyer* (freeware, 2000s). No code, art or sound from the original is used:
everything here is written from scratch, and all sounds are synthesised in code.
