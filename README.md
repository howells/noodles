# Noodles

A visual Node.js dev server manager for macOS. Lives in your menu bar, shows what's running, and lets you kill it.

![Screenshot placeholder](https://noodles.danielhowells.com/og.png)

## What it does

Noodles monitors your local dev servers and displays them in a compact popover from the menu bar.

- **Auto-detects running servers** by scanning listening ports (node, bun, deno, vite, next-server)
- **Port badges** -- click any port number to open `localhost` in your browser
- **Kill process trees** -- stop a server and all its child processes
- **View logs** -- reads from `~/.cache/noodles/logs/` when using the companion `ndev` shell function
- **Reveal terminal** -- jump to the terminal window that spawned the server
- **Remembers projects** -- previously seen servers stay in the list as stopped entries
- **Launch on login** -- optional, via macOS Login Items
- **Menu bar icon** -- a 2x2 dot grid where dots light up green for each running server

## Install

Download the latest DMG from [Releases](https://github.com/danielhowells/noodles/releases).

## Build from source

### Requirements

- macOS 13.0+
- Xcode 15+

### Steps

```bash
git clone https://github.com/danielhowells/noodles.git
cd noodles
open app/Noodles.xcodeproj
```

Build and run from Xcode (`Cmd+R`), or use the build script for a signed and notarized release:

```bash
./scripts/build.sh
```

The build script archives, signs with Developer ID, notarizes with Apple, and produces a DMG in `build/`.

## Optional: `ndev` shell function

Noodles can display dev server logs if you start servers with the included `ndev` Fish function. It wraps your package manager's `dev` script and tees output to `~/.cache/noodles/logs/`.

```fish
# Add to your Fish config
source /path/to/noodles/ndev.fish

# Then instead of `npm run dev`:
ndev
```

## Project structure

```
noodles/
  app/              # Swift macOS app (Xcode project)
  site/             # Marketing site (Next.js)
  scripts/          # Build and distribution scripts
  build/            # Build artifacts (DMG, xcarchive)
```

## License

MIT
