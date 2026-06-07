# Noodles

Noodles is a macOS local development service cleanup app.

It scans local TCP listeners, explains which project or tool appears to own each service, highlights memory-heavy processes, and lets you kill a service process tree with one click.

## Status

Noodles v2 replaces the original Swift menu bar app with:

- Go core for scanning, project detection, sorting, grouping, kill planning, and signal execution
- Wails desktop shell
- React/Vite operational table frontend
- CLI wrapper over the same core

The old Swift app remains under `app/` for reference while v2 reaches parity.

## Requirements

- macOS
- Go 1.26.2
- Node 24.x
- pnpm 10.x
- Wails v2 CLI for desktop development and packaging

## Development

Install frontend dependencies:

```bash
pnpm --dir frontend install
```

Run tests:

```bash
go test ./...
pnpm --dir frontend build
```

Run the CLI:

```bash
go run ./cmd/noodles list --sort memory
```

Run the frontend in browser-only mock mode:

```bash
pnpm --dir frontend dev --host 127.0.0.1
```

Run the Wails desktop app:

```bash
wails dev
```

## Project Structure

```text
.
├── cmd/noodles/        # CLI wrapper
├── desktop_app.go      # Wails-bound app methods
├── desktop_main.go     # Wails launcher
├── frontend/           # React/Vite UI and embedded dist
├── internal/app/       # Core scanner/view domain
├── internal/classifier/ # Service source labels
├── internal/desktop/   # Desktop service adapter and production wiring
├── internal/killer/    # Revalidated kill plans and signal execution
├── internal/ports/     # lsof listener collection
├── internal/processes/ # ps/lsof process enrichment
├── internal/projects/  # CWD to project identity
├── app/                # Legacy Swift implementation
└── site/               # Marketing site
```

## Safety Model

Kill requests are revalidated before signals are sent. The backend checks PID, process group, start time, command or executable path, CWD, project root, and expected ports against a fresh scan. If identity changed, no signal is sent.

Execution sends `SIGTERM`, waits a bounded grace period, then sends `SIGKILL` only for targets still alive.

## License

MIT
