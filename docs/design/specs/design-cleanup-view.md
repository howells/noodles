# Noodles Cleanup View

## Direction

Noodles is a quiet operational sniper tool for developers cleaning up local machine state after dev servers, agents, and browser tooling have left listeners running.

The first screen must answer: what can I kill right now?

## User

The user is a developer already under load. They are not exploring a process dashboard; they are trying to reclaim memory and ports without accidentally killing system, browser, or ambiguous root-owned processes.

## Interface Rules

- The primary section is `Cleanup candidates`: killable developer-owned services, sorted by memory by default.
- Unknown, system, browser, root-owned, or non-killable rows are `Other listeners`.
- `Other listeners` are review-only in the default UI. They must not receive one-click kill buttons.
- Memory gets stronger numeric treatment than source, age, or port metadata.
- CPU is hidden until the scanner can provide useful sampled values. Do not show `sample pending` as a table value.
- Project aggregate kill controls stay out of the default view until backend exclusions can make them trustworthy.
- The default view hides other listeners, but the user can reveal them without changing the cleanup candidate hierarchy.

## Visual System

- Inherit the Monogrove-derived Tailwind v4 token set in `frontend/src/style.css`.
- Use restrained borders and subtle surface shifts. Avoid wrapper panels and decorative cards.
- Button actions must be text-backed. Destructive controls use icon plus `Kill`, not icon-only red squares.
- Data rows stay dense, but every visible column must help a kill decision.
