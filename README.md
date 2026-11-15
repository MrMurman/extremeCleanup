# Extreme Cleanup

![Extreme Cleanup](docs/banner.jpg)

A desktop toy for macOS: take a hammer or a minigun to your screen, watch the glass crack, shatter and pile up at the
bottom. Or pick up the leaf blower: autumn branches slide in, leaves fall and settle on your icons and windows, and
you blow them off the screen. Built from scratch with AI, art included, as an homage to the 2000s classic
*Desktop Destroyer*.

**It never touches your files.** The app takes a snapshot of your screen and wrecks the picture. Press
Esc and your real desktop is exactly as you left it.

## Install

Requires macOS 14 or later, on Apple silicon or Intel.

> **Heads-up: macOS will warn you on first launch.** The app isn't sold through Apple or notarised by Apple, so
> macOS shows a scary dialog saying it can't check the app for malware, with a big **Move to Trash** button. Don't
> trash it: click **Done** and follow step 2. The full source is in this repo if you'd rather check it, or build
> it yourself (see [Build](#build)).
>
> **Prefer not to run unverified software?** A web version you can try in the browser is on the way.

**Scanned:** the 1.1.0 download has a [VirusTotal report](https://www.virustotal.com/gui/file/a683d8cb5b1181ebec0eda91b37fe0b683cad952ed56d83f906dd8caebe0c36e).
Its SHA-256 is `a683d8cb5b1181ebec0eda91b37fe0b683cad952ed56d83f906dd8caebe0c36e`; to check that your copy is the
same file, run `shasum -a 256 ExtremeCleanup-1.1.0.zip` in Terminal.

1. Download **ExtremeCleanup-<version>.zip** from [Releases](../../releases/latest) **in your browser**, unzip it
   and move **Extreme Cleanup** to Applications.
2. Open it. macOS stops it the first time:
   - **macOS 15 and later:** click **Done** on the warning. Open **System Settings › Privacy & Security**, scroll
     down to the message about Extreme Cleanup, click **Open Anyway** and confirm with your password or Touch ID.
   - **macOS 14:** right-click the app, choose **Open**, then **Open** again.
3. Allow **Screen Recording** when asked (**System Settings › Privacy & Security › Screen & System Audio
   Recording**), then quit and reopen the app.

You only do this once. Later versions are signed with the same certificate, so they open straight away and keep
the permission.

### "ExtremeCleanup can't be opened", with only an OK button?

That happens when a messenger such as Telegram saved the file for you: macOS then refuses to run it at all and
offers no **Open Anyway**. Download the zip from [Releases](../../releases/latest) in your browser instead. If you
already have the app and are comfortable with Terminal, this clears the block:

```sh
xattr -dr com.apple.quarantine /Applications/ExtremeCleanup.app
```

## Controls

The app opens with a small launcher: pick which displays to play on, which one shows the toolbelt, sound, music and
the leaf style (retro pixel art or realistic), then press **Start the cleanup**. Your choices are remembered.

| Key / mouse | Action |
|---|---|
| 1 / 2 / 3 | Pick a tool: hammer / minigun / leaf blower |
| Click | Hammer: one hit cracks, two widen the crack, three shatter the glass |
| Hold | Minigun: every round leaves a bullet hole; seven in one spot shatter it |
| Press and drag | Leaf blower: the press sets the nozzle, dragging aims the jet. A gentle jet slides leaves along, a strong one lifts them and blows them off the screen |
| M | Music on / off |
| C | Clean up: a broom sweeps the mess away, leaves included, and leaves a spotless desktop |
| Esc | Back to the launcher — your real desktop is untouched |
| ⌘Q | Quit |
| D | Debug overlay (frame rate, detected icons) |

## Permissions

- **Screen Recording** — to take the snapshot it smashes. Without it you get your wallpaper instead.
- **Automation → Finder** — read-only, to find where your desktop icons are.
- **No permission needed:** the app also reads where your open windows are (position and size only, nothing inside
  them), so falling leaves can settle on their top edges.

Newer macOS versions now and then ask you to confirm that an app may keep recording the screen. That happens to
every app that captures the screen; choose *Allow* to keep playing.

## Build

Requires macOS 14+ and the Xcode Command Line Tools.

```sh
scripts/bundle.sh                  # builds build/ExtremeCleanup.app
open build/ExtremeCleanup.app
```

Without the release signing certificate the build is signed ad-hoc: it runs the same, but macOS asks for Screen
Recording again after every rebuild.

## Credits

Inspired by *Desktop Destroyer* (freeware, 2000s). No code, art or sound from the original is used.

- **Code:** written from scratch with AI (Claude).
- **Sound and music:** synthesised in code; the app ships no audio files.
- **Autumn art:** the leaves and branches were generated with AI (ChatGPT, OpenAI's gpt-image model), together
  with a browser prototype of the leaf physics that the game's version grew from. `scripts/clean-autumn-art.py`
  prepares the generated images for the game.
- **Crack art:** the leaf blower's fracture textures were generated with AI (ChatGPT, OpenAI's gpt-image model);
  `scripts/build-fracture-crack-art.py` prepares them for the game.

## License

[MIT](LICENSE) © 2026 boroda studio.
