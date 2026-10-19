# Implementation and release boundary

The macOS feature set is implemented: nested docking and groups; native tab strips and tear-off; seams and miniatures; continuous camera and rectangle framing; saved views and history; optional still previews; AX observers; per-display layouts; exclusions; URL commands; configurable shortcuts; startup registration; matching and dormant reconnection; journal/recovery; import/export/backups; and universal packaging.

Live native acceptance remains separate from implemented code. The current run is checking the demo and disposable fixture windows; results belong in acceptance.md. Multiple physical displays, varied third-party apps, energy measurements, login approval, and notarization each need their own evidence.

Public distribution additionally needs the owner's Developer ID identity and notarytool profile. The implementation includes those commands; credentials are not supplied or guessed. GitHub publishing is not implied by building the source locally.

Windows support and distribution channels beyond the local macOS bundle are future scope. Public API gesture monitoring has an unavoidable first-event limitation; exclusive Overview is the supported alternative.
