# Canopy user guide

An independent, MIT-licensed macOS window manager inspired by [TrellisWM](https://trelliswm.app/). Windows belong to nested spaces: dock, group them as tabs, and zoom into the work you need.

**Version 0.8.2:** live resizing updates window geometry without raising workspace backgrounds over apps. Floating windows can fill empty slots, split beside a slot or the whole grid, or join a slot as tabs. Workspace switching retains the native layering introduced in 0.6.0. See [acceptance results](acceptance.md).

## Build and run

Requires macOS 14+, Xcode Command Line Tools, and Swift 6. No package dependencies.

```sh
swift test
bash scripts/build-app.sh debug native
open dist/Canopy.app --args --demo
```

The demo does not move real windows or overwrite the real workspace. Click **Use My Windows**, enable Canopy in Privacy & Security → Accessibility, then click the button again. The app starts paused. **Apply Grid** arranges only the windows you added to the selected grid; **Restore Windows** returns frames and pauses; **Resume Layout** reapplies the saved tree. Quitting restores windows Canopy moved or minimized.

Use the app bundle for permission identity and URL registration. Ad-hoc signatures change when code is rebuilt, so macOS may require re-enabling Accessibility. Public distribution uses Developer ID signing and notarization; local builds use `CANOPY_SIGNING_IDENTITY` or the ignored `.canopy-signing-identity` file when configured, otherwise an ad-hoc signature.

## Quick auto layout

Press **Control–Option–A** (or choose **Auto Layout Current Monitor** in the menu bar) with your pointer on the monitor you want to arrange. Canopy uses that monitor’s current Desktop windows: one fills the usable area, two divide it side by side, three use two columns with one stacked pair, and four form a 2×2 grid. Larger sets use balanced columns. Gaps and the workspace tab strip stay clear of app content.

The action updates the current grid on that monitor and supports Undo. Other grid tabs and monitors stay intact. Minimized, fullscreen, excluded, inactive-grid, and other-Desktop windows are skipped. A window crossing monitor boundaries belongs to the monitor containing most of its area. If the panes cannot meet native minimum sizes, the action leaves the windows alone. An app that rejects placement pauses only the target monitor. The global shortcut is configurable in Settings; an existing conflicting custom binding is preserved.

## Workspace grid tabs

Click **New Grid** to start empty. The sidebar separates **In this grid** from **Available windows**. Drag a window into the canvas or use its + button. Drop on a card edge to split, or in the center to create app tabs. Use − in the sidebar, × on an app tab, or drag to **Drop here to remove**. Removing a window keeps its app open and leaves other grids intact. Drag onto another workspace tab to move the window there; the destination opens after the drop. Use **Duplicate Grid** in a grid tab’s context menu when you want a copy. **Apply Grid** does not add unchosen windows; **Add All** is an explicit shortcut. Search filters the window lists. Right-click a tab to rename it; its × closes it. At least one grid remains. Undo restores a closed grid. Each display keeps its own tabs, and each tab has its own zoom, history, and saved-view slots. Windows can appear in different arrangements across tabs; only the active arrangement is applied to the desktop. Inactive-only windows remain managed until their grid is selected or Restore Windows is used. Each grid can contain its own subset of windows, including windows also used by another grid. Activating a window assigned to another workspace selects that workspace. Dock clicks and native focus events are reconciled against the activated process, with bounded retries while macOS updates focus or visibility. Stable native window IDs handle refreshed Accessibility references. Revealing a window outside the grid’s saved zoom shows the whole grid. Shared windows prefer an already active workspace; floating apps remain floating.

Use **Columns 1 / 2 / 3 / 4** to set full-height columns. Extra apps stack vertically within them. Drag an app onto a **Column N** header to stack it there, or into an empty column to fill it. Drop at a card’s left/right edge to create an adjacent column; use **Give Own Column** in its context menu for the same action. Empty columns stay available as drop targets. Known native minimum widths widen columns when the display has room; an arrangement that cannot fit safely is rejected. Changing the column count uses currently available windows in that grid and supports Undo.

Existing version 1/2 workspaces migrate to Grid 1. Version 4 preserves all grids and explicit empty columns and reads versions 1–3; older Canopy builds refuse to overwrite the newer format. Workspace backups remain in Application Support/Canopy/Backups.

## Desktop controls

While a grid is applied, workspace tabs sit below the macOS menu bar even when the editor is closed. Click a tab to switch its entire arrangement; **Edit Grids** reopens the editor. Canopy reserves 32 points above managed windows so the strip does not cover app controls. Restore or quitting removes the strip.

- Drag a floating window by its real title bar to preview docking without a modifier. An empty slot fills; another slot's edge creates a nested split; its middle adds a tab. Screen edges split beside the whole visible grid. Escape cancels. Moving a window already in the grid requires Option by default; this is configurable.
- Native tab strips join windows across apps. Click to select a tab, drag one out, or drag the strip's leading grip / hold Shift to move the whole group.
- Drag a desktop seam to resize both sides; double-click resets the split. Native updates coalesce to the latest pointer position without restacking apps or covering them with a background. Neighboring spaces retain their ratios, and a drag creates one Undo step.
- Small windows and small groups become clickable miniatures. Group miniatures retain their split outlines. Double-click to focus.
- Automatic grids contain app windows only. The Desktop shortcut restores floating windows without reserving a grid cell.
- **Overview** opens a continuous camera. Pinch to zoom around the pointer, scroll or drag to pan, and Shift-drag to frame an area. Releasing a pinch settles on the best-fitting space.
- Option-pinch outside Canopy enters Overview; pinching bare wallpaper and Shift-dragging wallpaper are also supported. macOS global monitors are passive: the initial event can reach the original app. Use the Overview button for exclusive camera input.
- Double-click a managed title bar to frame it. Breadcrumbs, Back/Forward, Everything, and saved views navigate the same tree.

In the inspector, drag a sidebar row, tab, or card body onto a card edge to split, or onto its center to make tabs. The highlighted region previews the destination; Escape cancels. Drag a tab to another edge to split it out. Seams resize neighboring panes; known app minimum sizes constrain subsequent edits. Undo/Redo treats a drag as one edit. Context menus and **Place Window** also support keyboard docking. Click an empty saved-view slot to save; click a filled one to recall; right-click to overwrite. Each display has nine independent views, including free framing rectangles.

Inactive tabs, off-camera windows, and windows represented by miniatures remain live behind a normal-level workspace background. Switching does not minimize apps. Restore also reverses minimization owned by older Canopy sessions. User-minimized windows keep their tree positions and temporarily give neighbors the space. Closed windows are removed; terminated apps retain dormant slots that reconnect when reopened.

Full-screen and other-Desktop windows are excluded from the live grid. Discovery requires a native window ID confirmed by WindowServer on the current Desktop. An optional macOS Accessibility SPI resolves the ID directly; if unavailable, discovery falls back to unique exact frame matching. This SPI is checked at runtime and may change in future macOS versions. Space transitions temporarily freeze writes; leaving all managed windows behind pauses arrangement. Return to the original Desktop to resume or restore.

## Workspace transitions

Switching brings the selected grid forward above a workspace background; inactive windows stay live behind it. There is no screenshot capture, waiting period, full-screen fade, or Dock minimization. Returning to an unchanged arrangement skips native geometry writes. Empty grid areas consume clicks so they cannot reach inactive windows behind the background. Floating windows stay available across grids.

First placement, layout edits, manual window moves, display changes, or using the same native window at different sizes in multiple grids still require geometry writes. A window shared by grids is one physical window, not a duplicate. These necessary writes are distinct from replaying every window on every switch.

Workspace switching needs Accessibility but no Screen Recording grant. **Animate zoom and layout edits** controls those separate actions. Restore, macOS Space changes, full-screen suspension, and quitting remove or hide the workspace backgrounds. Your original frames remain recoverable from the restoration journal.

## Previews and settings

**Show window contents** in Settings requests optional Screen Recording access. ScreenCaptureKit supplies still images only; no video or image files are recorded. The cache is bounded to 64 entries / 64 MiB and refreshes on a timer while arrangement or the inspector is visible. It clears when disabled.

Settings also includes configurable global shortcuts, docking modifiers, tab strips, animation, native-size thresholds, exclusions, launch at login, workspace import/export, backup/reset, and interrupted-session recovery. Launch at login uses SMAppService and can require approval in Login Items.

## Default keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Auto layout current monitor | Control + Option + A |
| Previous / next workspace | Option + Shift + Tab / Option + Tab |
| Workspace 1–9 in tab order | Control + Option + Command + number |
| Everything | Control + Option + Space |
| Desktop | Control + Option + D |
| Step out / toward pointer | Control + Option + Up / Down |
| Frame focused window | Control + Option + Return |
| Previous / next pane | Control + Option + Left / Right |
| Back / forward | Control + Option + [ / ] |
| Recall / save view 1–9 | Control + Option (+ Shift) + number |
| Undo / redo layout inside Canopy | Command + Z / Command + Shift + Z |

Workspace-cycle defaults are Option–Tab forward and Option–Shift–Tab backward. Cycling skips empty grids and grids with no available windows on this Desktop. Existing default cycle bindings migrate; customized and disabled bindings remain unchanged. Workspace shortcuts work while another app is focused, and select without arranging when Canopy is paused. Existing pane/view shortcuts retain their bindings. Upgrades add missing workspace bindings; if a new default conflicts with a customization, that new binding starts disabled.

Click a shortcut in Settings to record a replacement. Escape cancels; Delete disables it. Internal duplicates are rejected and system conflicts are reported.

## URL commands

```sh
open canopy://arrange
open canopy://float
open canopy://resume
open canopy://everything
open canopy://desktop
open canopy://overview
open canopy://frame
open canopy://zoom-in
open canopy://zoom-out
open canopy://back
open canopy://forward
open canopy://next
open canopy://previous
open canopy://undo
open canopy://redo
open canopy://save/1
open canopy://view/1
open canopy://clear-view/1
open canopy://recover
```

Also supported: `canopy://focus/<node-id>`, `canopy://select/<window-id>`, `canopy://float/<window-id>`, and `canopy://dock?window=<id-or-focused>&target=<node-id>&edge=left&group=true`. A `display=<id-or-name>` query selects a display. IDs are in exported workspace JSON. Docking and structural edits stay paused unless arrangement is active. URLs cannot leave demo mode or bypass permissions. `pause` aliases restore-and-pause.

## Storage and recovery

State is atomically written to `~/Library/Application Support/Canopy/workspace.json`. It contains local window metadata, layouts, preferences, original frames, and a restoration journal. Data stays on the Mac; no network calls or telemetry are used.

Baselines are persisted before moving or minimizing a window. After a crash, **Recover Windows** restores matching windows explicitly; startup never moves them automatically. SIGTERM and SIGINT request a graceful quit. SIGKILL or an OS crash cannot run cleanup. Missing apps can be reopened before retrying recovery. Frames are clamped onto connected displays when restored.

Window matching uses Accessibility identity within a session and bundle ID, document, AX identifier, title, occurrence, and geometry after relaunch. Ambiguous fingerprints stay unmatched. This remains a best-effort public-API match. Invalid or newer-version state is preserved with saving disabled; backup/reset repairs it without deleting the previous file. Imports validate first, back up current state, and start paused. Exports omit the machine's active recovery journal.

## Isolated native testing

```sh
bash scripts/build-test-app.sh
open dist/CanopyFixture.app
open "dist/test/Canopy Test.app"
```

The test script builds **Canopy Test** in `dist/test` with its own bundle identifier, keeping it separate from the full **Canopy** app and its permission identity. It does not register normal Canopy URL commands. The full app remains `dist/Canopy.app`; installation rejects fixture-only builds. Alternatively, pass `--demo --test-fixture` to a normal bundle for a temporary scoped session. Fixture mode only discovers `org.canopywm.Fixture`, disables global wallpaper gestures by default, and uses `Canopy/TestSessions/fixture-workspace.json`. It cannot arrange personal-app windows. The disposable helper includes duplicate titles, stable identifiers, renaming, different minimum sizes, and an **Export Window Frames** button for quantitative restoration checks.

Automated tests use injected bridges and temporary files; they need no Accessibility or Screen Recording permissions.

## Release and installation

```sh
bash scripts/release.sh
bash scripts/install.sh
```

The release script compiles arm64 and x86_64, generates the original icon, verifies signing, and produces a universal app ZIP, source archive, and checksums. CI runs tests and uploads those artifacts.

Set `CANOPY_OUTPUT_DIR` to build into another directory, such as `dist/release`, while preserving a permission-authorized test bundle in `dist`. Release builds always remove fixture mode. The latest local universal artifacts are in `dist/release`.

For a notarized build, set `CANOPY_SIGNING_IDENTITY` to your Developer ID Application identity and `CANOPY_NOTARY_PROFILE` to an existing notarytool keychain profile, then run `bash scripts/release.sh --notarize`. This submits the artifact to Apple; it is not run automatically during local development.

Install defaults to `~/Applications/Canopy.app` and backs up an existing Canopy bundle. Disable Launch at Login and quit before `bash scripts/uninstall.sh`; uninstall moves the bundle to Trash and preserves workspace data. `scripts/profile.sh` records local process statistics and a five-second stack sample for energy/performance investigation.

## Source map

- `CanopyCore`: split/tab tree, docking resolution, geometry, camera, history, and matching.
- `WorkspaceStore`, `DesktopPlan`, `WorkspaceFiles`: per-display state, native placement policy, journal, and storage.
- `WindowBridge`, `WindowEvents`: public Accessibility operations, AX notifications, and app lifecycle.
- `WindowPreviews`: ScreenCaptureKit and bounded in-memory cache.
- `DesktopOverlays`, `DesktopViews`: native tabs, seams, miniatures, docking feedback, camera, and motion.
- `WorkspaceView`, `AppSettings`, `HotKeys`: inspector, onboarding, settings, and commands.
- `CanopyFixture`: disposable native acceptance helper.

See [architecture](architecture.md), [implementation status](implementation.md), and [contribution guidance](../CONTRIBUTING.md). Windows support is a separate future backend. Canopy is independently implemented and is not affiliated with Trellis.
