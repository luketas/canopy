# Changelog

## 0.8.1 — 2026-10-26

Add configurable global Control–Option–A auto layout on the monitor under the pointer. Two windows use equal side-by-side columns; four use two columns with two rows each, independent of monitor aspect ratio. Other counts use balanced columns. Enroll only available current-Desktop windows on that monitor, skipping minimized, fullscreen, excluded, and inactive-grid windows. Preserve other tabs and off-Desktop memberships. Start monitor-local arrangement sessions without applying saved layouts to other monitors; scope native writes, stacking, recovery adoption, and placement-rejection rollback to the target display. Add the action to the menu bar.

## 0.8.0 — 2026-10-26

Move native live-resize IPC off the input thread, keep only the latest pending geometry, and read frames at the start and end of a gesture. Fence outstanding writes before restoring or switching workspaces. Stop reapplying the desktop for title-only notifications.

Route native app/window activation to its existing workspace instead of leaving inactive-grid windows above the current grid. Preserve shared-window membership and current-Desktop boundaries. Use Option–Tab / Option–Shift–Tab to cycle nonempty available workspaces, migrating old defaults while preserving customized, disabled, and conflicting bindings. Add shortcut hints to the desktop workspace bar. Keep saved shared-display layouts loadable and plan each shared native window once, with connected-display focus routing.

## 0.7.0 — 2026-10-19

Give live resizing a geometry-only path: coalesce pointer updates on the common run loop, skip activation and background restacking, reposition existing seam controls, and save once on release. Skip unchanged native position/size writes and temporarily suppress accessibility-enhanced resize animation for participating apps. Keep seam deltas relative to the initial geometry.

Allow floating title-bar drags to dock without Option. Fill empty columns and empty grids, split at slot or screen edges, and tab at slot centers. Resolve gutter drops against nearby slots, choose source windows in native stacking order, reuse the preview panel, and cancel with Escape. Track native movement while macOS owns the title-bar drag loop. Permit windows brought forward from another Canopy grid to dock into the current grid without losing their other arrangements.

## 0.6.0 — 2026-10-18

Replace the capture-and-wait workspace transition with native window layering. Keep inactive windows live behind a workspace background instead of minimizing them. Returning to unchanged grids skips frame writes. Activate the selected app before raising companion windows, then place the background behind all active windows. Consume empty-area clicks, preserve floating windows, remove backgrounds on suspension/restore, and retain older restoration journals. Workspace switching no longer needs Screen Recording access; optional previews remain separate.

## 0.5.1 — 2026-10-18

Remove workspace crossfades and whole-screen opacity animation. Hold captured pixels opaque until native windows have stayed ready, then reveal the destination once, without animation. Include a brief settling interval for Dock animation after geometry changes. Keep this quiet masking with Reduce Motion and disabled zoom/layout animation. Give editor workspace canvases separate identities so unrelated grids no longer morph into one another. Preserve the confirmed global workspace shortcuts.

## 0.5.0 — 2026-10-18

Mask intermediate AX resizing and Dock animation with a short-lived ScreenCaptureKit image, then crossfade after native windows settle. Keep workspace tabs above the captured area and update selection immediately. Coalesce rapid requests onto one capture, reject stale completions, rebase interrupted fades, honor Reduce Motion, and bound capture/settling waits. Restore, Space changes, and shutdown remove the covers. Capture requires an existing Screen Recording grant and never writes image files.

Add configurable global previous/next workspace and workspace 1–9 shortcuts, separate from pane navigation and saved views. Preserve existing bindings and disable newly introduced defaults when they conflict with a customization. Combine registered Carbon hotkeys with AppKit delivery and deduplicate identical timestamps; unregistered conflicting chords are not intercepted. Add a workspace menu and clarify Settings labels.

## 0.4.0 — 2026-10-18

Add explicit 1–4 column presets, labeled stack drop targets, empty column slots, adjacent new-column drops, and Give Own Column. Presets use available current-Desktop windows from the selected grid. Preserve empty-column geometry without creating managed app records. Fit demonstrated native minimum widths across columns before reverting an impossible edit. Moving the final app out of a column assigns detached identities so the preserved empty slot remains usable. Version 4 storage reads legacy versions 1–3.

Add a native workspace tab strip below the menu bar while arranging, with the editor closed or open. Reserve its height above app frames. Keep the strip and its native accessible buttons alive across layout updates, including repeated switching. Edit Grids recreates a closed editor through SwiftUI window routing. Restore, full-screen suspension, and shutdown remove or hide desktop controls.

## 0.3.1 — 2026-10-18

New grids start empty, with duplication available explicitly. Split the searchable sidebar into current-grid and available windows, with visible add/remove buttons. Add per-app removal controls, a persistent drag-out removal zone, and drop targets on workspace tabs for transferring windows. Transfers balance destination leaves into usable cells. Apply Grid preserves explicit membership instead of enrolling every available window. Removal affects only the selected grid, preserves other grids and restoration ownership, and supports Undo.

## 0.3.0 — 2026-10-18

Add workspace tabs across the top. Each tab owns an independent grid, zoom, history, and saved views. New Grid duplicates the current arrangement; tabs support renaming, closing, and Undo. Version 3 storage migrates legacy workspaces to Grid 1. Restoration ownership spans all grids, and closed windows are pruned from inactive grids too.

Fix white flashes during tab switches: skip full-display transitions for tab-only changes, draw only actual preview images on transparent transition panels, cancel interrupted timers/panels, and use the common run-loop mode. Reveal, position, and raise the replacement before hiding the outgoing window. Skip redundant native frame writes. Editor tab clicks keep focus in Canopy; desktop tab clicks activate the selected app before minimizing the old tab.

## 0.2.3 — 2026-10-18

Replace unreliable inspector dragging with an editor-owned mouse sequence. Sidebar rows, card bodies, and tab headers now share split/tab targets, visible destination feedback, Escape cancellation, and one-step undo. Clip recursive panes to their geometry and retain tab headers in compact cards. Double-click focuses and returns through navigation history; stale history falls back to the whole layout.

Apply seam resizing continuously, constrain later edits using demonstrated native minimum sizes, and roll back a rejected edit to the last verified layout while keeping arrangement active. Restore newly floating inactive tabs and keep overlay controls stable during drags.

Resolve actual native window IDs through optional runtime Accessibility SPI with a unique exact-frame fallback. Merge duplicate AX references without losing their restoration baseline or layout position; distinguish replaced onboarding windows from a new main window. Refresh before restoration and clear stale failure messages when a late closure notification removes its journal entry.

Real mouse and native-app acceptance is recorded in docs/acceptance.md, including the limits of reference-app inspection and the remaining hardware/gesture checks.

## 0.2.2 — 2026-10-18

Automatic grids now contain app windows only. Live panes and the sidebar omit dormant, closed, and other-Desktop windows. Native matching uses exact bounds and current on-screen window IDs rather than a nearest-window guess or a default-visible fallback. Confirmed invalid AX elements remove their layout and recovery state. Fixed-width windows can leave spare space inside their cells without triggering rollback; overflowing windows still fail verification. Crowded initial layouts group windows into tabs. Recalling an unavailable saved view cannot hide every current app.

Real-app acceptance fixes: balance initial panes into columns and rows so ordinary Chrome windows do not receive unusably shallow slots; retain layouts when macOS omits windows on other Desktops; preserve browser identity across same-process relaunches using an unambiguous native window number; and check actual managed-window visibility before pausing for a Space notification. Temporarily suspend Enhanced UI animation during native frame writes and restore its original state afterward. Local builds can retain a development signing identity in an ignored `.canopy-signing-identity` file so rebuilds keep the same Accessibility identity.

The development run exercised actual Chrome, Finder, and TextEdit windows: arrangement, input, zoom and return, native cross-app tabs, split resizing and undo, view save/recall, and exact restoration. A later run arranged current-Desktop Chrome, GitHub Desktop, System Settings, and WhatsApp while excluding off-Desktop Obsidian, then exercised native input, zoom, cross-app tabs, undo, closure cleanup, and exact restoration. Native evidence and the remaining acceptance scope are recorded in docs/acceptance.md.

## 0.2.1 — 2026-10-18

Fix click-blocking desktop controls after arrangement: keep the Desktop control to a small button, activate miniatures with one click, and stop inferring minimum window sizes from rejected Accessibility writes. A failed settled resize now removes overlays, restores windows, and pauses. Initial arrangements that cannot fit active windows stop before changing native frames or minimization. Four new regressions cover rollback, cramped layouts, ordinary clicks, and Desktop control bounds.

## 0.2.0 — 2026-10-14

Implemented the remaining macOS workflow: native desktop docking and previews, desktop tab strips and group tear-off, seam controls, miniature spaces, continuous camera and rectangle framing, optional ScreenCaptureKit still images, AX event observers, richer window fingerprints, dormant app reconnection, a restoration journal, import/export and backups, configurable shortcuts, launch at login, and universal release tooling.

The implementation builds for Apple silicon and Intel. Automated tests use injected window/capture bridges. A disposable native fixture is included for acceptance runs. Real desktop, gesture, permission, and visual verification remain separate from compilation and automated tests.

Native acceptance fixes on October 18: preserve omitted minimized/off-Space window elements and restoration baselines, track minimize requests through Dock animations, verify placement after settling, and keep missing-window restoration retryable. The controlled native fixture now explicitly implements its public Accessibility frame/minimized contract. 63 automated tests pass; native smoke and exact restoration results are recorded in docs/acceptance.md.

Separate fixture builds as **Canopy Test** (`org.canopywm.Canopy.Test`) in `dist/test`, without normal URL registration. Preserve the full app at `dist/Canopy.app` and reject fixture builds during installation, preventing the test instance from intercepting normal launches.

## 0.1.0 — 2026-10-14

Initial native workspace inspector, split/tab layout engine, per-display state, saved views, navigation, Accessibility bridge, and demo mode.
