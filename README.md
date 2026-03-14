# NFL2K5Tool Web

A browser-based editor for NFL 2K5 gamesave files. Load a save, edit players, schedules, and coaches, then export back to your console format — no installation required.

![NFL2K5Tool Web](web/NFL2K5_image.webp)

[https://BAD-AL.github.io/nfl2k5tool_web/](https://BAD-AL.github.io/nfl2k5tool_web/)

---

## Features

- **Player Editor** — Edit attributes, appearance, identity, and stats for every player on every team. Includes a face photo picker with the full player photo library built in.
- **Schedule Editor** — View and edit the franchise schedule via a weekly grid, team matrix, and integrity checker.
- **Text Editor** — Direct access to the underlying text representation of the save data, with search, line numbers, and wrap toggle.
- **Options** — Control which sections are included in the text output (players, schedule, appearance, attributes, free agents, draft class, coaches).
- **Export** — Export back to your original format or convert between Xbox and PS2 formats.

---

## Supported File Formats

| Extension | Format |
|---|---|
| `.zip` | Xbox save (zip archive) |
| `.bin` / `.img` | Xbox Memory Unit |
| `.max` / `.psu` | PS2 save |
| `.ps2` | PS2 Memory Card |
| `.dat` | Raw DAT |

### Format conversion rules

- **Xbox saves** (`.zip`, `.bin`, `.img`) can be exported to any format
- **PS2 saves** (`.ps2`, `.max`, `.psu`) can be exported to PS2 formats and raw DAT
- **Raw DAT** (`.dat`) can only be exported as raw DAT
- Memory card exports (`.bin`, `.img`, `.ps2`) are written to a fresh card

---

## Usage

1. Open the app in your browser
2. Click **Open** and select your gamesave file
3. Use the nav rail on the left to switch between editors
4. Edit players, schedule, or raw text as needed
5. Click **Export** to download the modified save

---

## Dependencies

- [nfl2k5tool_dart](https://github.com/BAD-AL/nfl2k5tool_dart) — binary decode/encode engine
- [archive](https://pub.dev/packages/archive) — ZIP handling for the photo library
- [web](https://pub.dev/packages/web) — Dart browser bindings

---

## Notes

- No data is sent to any server — everything runs locally in the browser
- The full player face photo library is embedded in the app (~19 MB total)


Setup docs/ folder (GitHub pages):
  1. Run webdev build
  2. Copy build/web/ contents → docs/ in your repo root
  3. Push to main
  4. In repo Settings → Pages → set source to "main branch / docs folder"
  5. Browse to: https://BAD-AL.github.io/nfl2k5tool_web/