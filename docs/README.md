# Agent documentation index

Start with [AGENTS.md](../AGENTS.md), the repository's agent entry point. These focused references supplement its rules; they do not replace them.

| Reference | When to read it |
| --- | --- |
| [Source map](source-map.md) | Locating the subsystem, production boundary, and existing tests for a change. |
| [Player UX audit](player-ux-review.md) | Player interaction references, root causes and verification scope. |
| [Playback](playback.md) | Modifying playback state, full/mini-player, Media3/PiP, sleep timers or playback preferences. |
| [Testing and verification](testing.md) | Choosing checks and reporting what the evidence establishes. |
| [Known limitations](known-limitations.md) | Changing transfers, persistence, extraction, playback, or Android background behavior. |
| [Architecture](../ARCHITECTURE.md) | Understanding ownership, data flow, and extension points. |
| [Contributing](../CONTRIBUTING.md) | Preparing an issue, platform integration, or pull request. |

## Evidence rules

- Inspect the working tree before editing. Preserve unrelated edits, stored user data, completed files, and partial downloads.
- Confirm current implementation in the linked source and dependency versions in `pubspec.lock`. A declared package does not prove that its feature is wired into production.
- Treat `AGENTS.md` as required compatibility constraints. If current code contradicts a documented contract, describe the discrepancy and investigate before changing either one.
- Find existing symbols with `rg`; do not assume a class, method, route, schema, or command exists because a similar project uses it.
- Distinguish source inspection, fixture coverage, live requests, device observations, and untested hypotheses. A test file's presence is not a test pass.
- Never invent verification results, test counts, benchmark improvements, or guarantees of live source availability. Report only checks actually executed and include failures and blocked checks.
- Use existing adapters and shared policies. Document a new boundary only after it exists in production; label proposals explicitly.

Update these references alongside changes to their owning subsystem. Keep source paths and commands concrete; avoid copied session reports, speculative implementation plans, and duplicate rules that drift independently.
