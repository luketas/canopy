# Native acceptance checks

Current automated evidence: **128 tests pass (33 XCTest and 95 Swift Testing)** on 2026-10-19. Native evidence below separates controlled fixtures, development runs against actual third-party apps, and final-package smoke checks. Physical multiple displays remain unverified.

Environment: macOS 26.2 (25C56), Apple silicon, Apple Swift 6.2. The native test session uses `scripts/build-test-app.sh` and `dist/CanopyFixture.app`. This embeds restricted discovery in the test bundle and isolates persistence under `Canopy/TestSessions`. Export Window Frames records the fixture's own actual geometry. The baseline includes three 640 × 432 windows, with two duplicate titles, at (100, 828), (210, 758), and (320, 688). Compare after Arrange and Restore; do not substitute source assertions for native frame evidence.

Additional native observations: shortcut recording enters its waiting state and Escape preserves the existing combination. The finish reviewer returned **fix** for default-window clipping, icon-only primary actions, and Desktop reusing Notes visuals. One batch bounds the sidebar and its scrolling list, adds explicit toolbar labels, and gives Desktop a distinct icon, compact label, and demo content. On 2026-10-18, a valid unlocked 1160 × 760 screenshot confirmed these three visible corrections: heading/help and footer fit; Use My Windows retains text; Desktop has its monitor icon and label.

The renewed reviewer scored all three fixes **resolved**, disposition **ship** for that fix list, after inspecting exact 1160 × 760 and expanded 3440 × 1410. The expanded view also confirms Desktop-specific content. The window was returned to 1160 × 760. No broader native-behavior approval is implied.

On 2026-10-18, System Settings initially showed Canopy's Accessibility switch **on**, but `AXIsProcessTrusted()` was false even after relaunch. The user authorized refreshing only Canopy's grant. Toggling alone did not resolve it; removing its stale entry and selecting the exact current bundle did. The user completed the later Touch ID prompt directly. No TCC reset, other-app permission change, or personal-window arrangement was used.

## Version 0.7.0 live resizing and floating docking — 2026-10-19

The geometry-only resize path skips activation, raising, background restacking, transition overlays, and intermediate persistence. A real editor-seam drag resized Muse from 1822 to 2101 points wide and ChatGPT from 1594 to 1315 points wide; native readbacks matched the requested frames. The latest live resize trace recorded 25 geometry updates with zero workspace-background ordering calls. These observations establish native geometry and the eliminated restacking path, not a frame-by-frame video or subjective no-blink certification.

A disposable Grid 3 initially contained GitHub Desktop and an empty column. The user first reported no preview or docking. Correcting global mouse handling to use the event's WindowServer coordinates resolved that check: the user explicitly reported **Preview and docking work**. The persisted native test grid then contained Finder in the right column and Chrome split above GitHub Desktop on the left. Floating drags do not require Option; grid-window drags retain their configurable modifier requirement. Source detection also supports unified toolbar regions while requiring actual native movement, so ordinary toolbar clicks cannot dock a window. A later user report isolated Obsidian and ChatGPT, which were assigned to other grids. Removing the hit-test exclusion for inactive-grid membership fixed both; the user physically confirmed **Both work**. Their original grids remained intact.

Automated regressions cover coalesced resize writes, one Undo step, final flushing, cancellation on pause, empty column fills, first-window docking into an empty grid, gutter targeting, and screen-edge splitting beside the whole tree. See `acceptance-evidence/2026-10-19-resize-floating-docking-development.json`. Native title-bar dragging by the control tool did not move Chrome or Finder; the physical user check above is the acceptance evidence for that path. The signed universal 0.7.0 build 14 relaunched with the six-app Grid 3 intact, applied it without an error, accepted History/Changes input in GitHub Desktop, and restored in one click. It was left arranging Grid 3 with the editor closed. The three original grids were preserved. See `acceptance-evidence/2026-10-19-resize-floating-docking-final-universal.json`. A development restore had needed one delayed retry; the final package check did not.

## Version 0.6.0 live workspace layering — 2026-10-18

The user rejected the capture-and-wait approach. This version removes that pipeline completely. Inactive windows remain live behind a normal-level background, and switching raises the selected grid. A target cache plus actual frame readback avoids unchanged geometry writes. Empty-area clicks stop at the background; floating windows are raised above it. First visits, changed geometry, and windows shared between differently sized grids still require placement.

The previous capture scheduler tests were removed with that implementation. New regressions cover 40 repeated workspace selections with no movement or minimization, changed-frame repair, activation before companion raises, background input handling, and restoration. The suite passes 122 tests (33 XCTest + 89 Swift Testing). Native development checks exposed and corrected activation order: companion windows must be raised after activating the destination app. The final packaged-build record below is separate from these automated checks.

An unattended native audit completed eight switches between Obsidian in Grid 1 and Muse/ChatGPT in Focus, preserving Chrome, GitHub Desktop, and Finder as floating windows. All eight settled window-order checks passed. The six return switches issued zero frame writes, left all managed windows unminimized, and had a median native transaction time of about 33 ms (API duration, not a frame-by-frame latency claim). Wallpaper loading was moved off the main thread after a native startup stall. The installed, signature-verified universal 0.6.0 build 13 then passed four direct keyboard switches, four pointer workspace clicks, and one-click Restore. The two earlier recovery entries remained intact. See `acceptance-evidence/2026-10-18-live-layering-development.json` and `acceptance-evidence/2026-10-18-live-layering-final-universal.json`.

## Version 0.5.1 quiet workspace reveals — 2026-10-18

The user physically confirmed that global workspace switching works while another app is focused, but rejected the amount of animation. Their feedback supersedes the prior subjective transition assessment. The implementation removes full-screen fading rather than tuning its duration: the old view stays opaque while native writes complete, remains held for at least 320 ms after applying, and reveals only after frames stay ready for 80 ms (with the existing bounded deadline). There is no opacity interpolation or fade completion callback. The editor canvas identity now changes per workspace, preventing unrelated grid morphs. Existing zoom/layout edit animation is separately labeled in Settings; workspace masking remains quiet with Reduce Motion and that setting disabled.

The regression suite still has 124 passing checks (33 XCTest + 91 Swift Testing), with the previous fade checks replaced by opaque holding, stable-frame readiness, single reveal, cancellation, and latest-request checks. The native development and universal-package acceptance records below remain separate from compilation. Before updating the previous build, WhatsApp restoration required one delayed retry; it succeeded and only the two earlier recovery entries remained.

The installed universal 0.5.1 build 12 completed four direct keyboard switches and four physical tab clicks between Focus (Chrome) and Grid 2 (Muse and ChatGPT). Restore succeeded on one click, disabled its button, and preserved only the two earlier recovery entries. The development run separately recorded six captures, six stable-frame settlements, and six single unanimated reveals. The signed universal binary was reverified and left running with Grid 2 active and the editor closed. These observations do not claim subjective user acceptance of the new treatment or frame-by-frame video certification. See `acceptance-evidence/2026-10-18-quiet-switching-final-universal.json`.

## Version 0.5.0 smooth switching and workspace shortcuts — 2026-10-18

Workspace changes now use a short-lived captured desktop image below the live tab strip, covering sequential Accessibility writes and Dock animation before a bounded crossfade. Rapid requests reuse the in-flight capture and apply the newest selection. Capture, settling, stale callbacks, cancellation, opacity progression, missing access, disabled motion, shortcut migration/conflicts, modifier matching, command routing, and deferred native writes have regression coverage. Existing short fixed animation test sleeps were replaced with bounded completion waits to avoid main-actor scheduling flakes.

The user approved Canopy’s Screen Recording grant and completed the Touch ID prompt themselves; System Settings visibly confirmed the switch on. Native development telemetry then confirmed capture-started, snapshot-presented, layout-applied, windows-settled, finished in order with actual third-party apps. Canopy’s directly delivered key events initially bypassed Carbon; the AppKit path then selected Grid 3 using the fourth workspace shortcut and Grid 4 using Next Workspace. Background physical-keyboard acceptance and final universal smoke are recorded separately when complete. No claim about every intermediate video frame is inferred from event telemetry.

The final compositor build completed seven captured transitions, all reaching windows-settled and finished with no capture fallback or settling deadline. Six successive directly delivered workspace shortcuts selected the expected destinations. A prior run completed eight native tab actions and coalesced two replacement requests onto one capture. The universal 0.5.0 build 11 then passed four more directly delivered shortcuts and four physical desktop-tab clicks with the editor closed. GitHub accepted physical History/Changes clicks after the transitions. Restore completed without errors and left only the two earlier recovery entries. The physical background-shortcut question was pending at packaging because the CUA key API posts directly to a target app; the user subsequently confirmed that it switches workspaces. See the separate smooth-switching evidence files.

GitHub Desktop crashed once during the earlier direct-key-event test. Its local report showed EXC_BAD_ACCESS inside Electron’s event dispatch; no cause is assigned to Canopy from that report alone. GitHub was subsequently relaunched and managed normally. The rest of the app’s private data was not inspected.

## Version 0.4.0 columns and desktop workspace tabs — 2026-10-18

The editor offers 1–4 columns with full-height labeled drop headers, vertical stacking, preserved empty drop slots, adjacent column creation, and Give Own Column. Presets omit unavailable old membership instead of allocating phantom cells. Undo preserves the previous tree. Version 4 persists explicit column structure while reading older versions.

Live development acceptance used GitHub Desktop, Chrome, WhatsApp, and System Settings on a 3440 × 1440 display. Three columns placed GitHub and Chrome vertically in the first column and the other apps in full columns. Give Own Column restored four full columns. Physically dropping Chrome onto Column 1 stacked it; dropping back into the empty fourth slot restored its full column. The first run found a duplicate layout identity after moving the sole app out of a column. The corrected build passed the same stack-and-return sequence, with unique identities and a Codable regression.

Four actual native frames fit below the desktop strip: GitHub (8,70,960,1362), WhatsApp (976,70,813,1362), System Settings (1797,70,723,1362), Chrome (2619,70,813,1362). System Settings caps its width within its cell. GitHub’s demonstrated 960-point minimum widened its column rather than collapsing the fourth column. The stacked frames were GitHub (8,70,960,677) and Chrome (8,755,960,677).

The native desktop strip occupies (0,30,3440,32), with app content starting at y=70. With the editor closed, ten successive accessible-button switches and six physical alternating clicks each confirmed the selected workspace after every action. Recreating the strip during layout updates had dropped clicks; keeping panels and native buttons stable resolved that sequence. Edit Grids initially failed after the editor closed; SwiftUI window routing then visibly reopened it. Native screenshots were observed through the CUA tool, not saved as files. These observations do not certify every intermediate animation frame or physical multi-display behavior.

Restore after the development run returned all six current-session windows exactly to their captured baselines: Finder, GitHub Desktop, Chrome, Muse, System Settings, and WhatsApp. The two older recovery entries remain preserved. The independent visual reviewer returned **ship** for editor sizes 1160 × 760 and 850 × 612 and the 3440 × 32 strip; this scope excludes window movement. See `acceptance-evidence/2026-10-18-columns.json` and `2026-10-18-columns-ui-review.md`.

The final universal 0.4.0 build 10 retained Accessibility and its four-column layout at the canonical app path. After unlocking, it arranged four real apps, accepted physical Chrome-to-column-header stacking and a return drag into the empty fourth column, and passed eight physical switches between Grid 3 and Grid 4 with the editor closed. The selected tab was asserted after every switch. GitHub Desktop accepted physical History and Changes clicks while arranged; Edit Grids reopened the closed editor. Restore completed in one click without a failure message, cleared six current-session restoration entries, and preserved the two earlier entries. A fresh native screenshot independently confirmed GitHub returned to its original 1277 × 734 size. Canopy was left open and paused with Grid 4 selected. See `acceptance-evidence/2026-10-18-columns-final-universal.json`. These results do not certify physical multi-display behavior or every intermediate animation frame.

## Version 0.3.1 explicit grid membership — 2026-10-18

New Grid starts empty; Duplicate Grid is explicit. The sidebar separates included and available windows, offers search and visible +/− controls, and each app tab has a removal control. Dragging to the persistent removal zone removes from the current grid. Dropping on another workspace tab transfers membership and opens that grid. Automatic transfer placement balances destination leaves into usable cells rather than squeezing existing columns. Apply Grid applies only the chosen membership; Add All explicitly adds available windows.

Live development acceptance created Grid 2 with GitHub Desktop and Chrome and Grid 3 with Muse and WhatsApp. Plus, edge drag, app-tab removal, drag-out removal, Undo, and transfers onto workspace tabs were exercised physically. Applying preserved the selected two windows. An initially rejected three-window transfer exposed narrow destination columns; balanced transfer placement fixed it. The corrected build then completed 12 switches between different app sets while arrangement remained active. Restore completed without failures.

The fresh native UI review inspected 1160 × 760 and the actual minimum total window size of 850 × 612 (560-point SwiftUI content height plus native chrome). It found Apply Grid overflowed at the smaller width. Recovery was moved to the File and menu-bar menus so Apply Grid stays visible. Scope and final verdict are recorded in the separate membership evidence; full VoiceOver and keyboard navigation are not certified by this visual check.

The final universal 0.3.1 build 9 retained the distinct app sets after relaunch. Search filtered available windows correctly. A first Finder window was physically dragged into an empty test grid; Apply Grid enrolled only Finder. The sidebar minus removed the last window, and the disposable grid was closed. Four more switches between Grid 2 and Grid 3 retained two distinct app sets, and GitHub Desktop accepted History input. Restore completed without errors; recovery remained in the File menu. The independent verdict pass scored both UI findings resolved with **ship** scoped to those findings. Canopy was left paused with Grid 2 selected; two earlier recovery entries were preserved. See `acceptance-evidence/2026-10-18-grid-membership-final-universal.json` and the scoped UI report.

## Version 0.3.0 workspace grids and tab transitions — 2026-10-18

Tab-only changes previously created a full-display transition panel whose drawing code filled the screen with the system window background, including when Screen Recording previews were unavailable. Transition timers used the default run-loop mode and could be interrupted by further mouse tracking. The fix skips display transitions for tab selection, removes all opaque background/placeholder painting from transition views, explicitly stops interrupted timers/panels, and schedules timers in common modes. The no-preview bitmap regression confirms every pixel stays transparent. Repeated cancellation tests verify a subsequent transition still completes.

Native switching now reveals, positions, and raises the replacement before minimizing the outgoing tab. Repeated requests for an already-settled frame skip redundant AX writes. Clicking an inspector tab keeps focus in Canopy instead of activating another app and potentially following its other Desktop. Native desktop tab clicks activate the selected app before hiding the outgoing window; activation order has automated coverage, while the repeated live clicks below used inspector tabs.

Workspace tabs now appear across the top. New Grid copies the active arrangement into an independent editable tab. Each grid retains its tree, zoom, history, and saved views, with rename, close, Undo, and version 3 persistence. Window ownership spans all grid tabs; closing a grid restores only windows no longer owned anywhere. Closed native windows are pruned from inactive grids. Legacy versions migrate to Grid 1; a pre-migration workspace backup was saved locally.

The corrected development build completed 16 physical switches between two distinct native arrangements and 24 app-tab switches with five current-Desktop apps present and arrangement active. Grid 2 was edited by dragging Chrome into Muse's group, renamed Focus through its context menu, and persisted with a different tree from Grid 1. GitHub Desktop accepted a History click after the cycles. Restore completed in one click without a failure message; two earlier unresolved recovery entries remain preserved. See `acceptance-evidence/2026-10-18-workspace-tabs.json` and the separate final universal-build record.

The final universal 0.3.0 build 8 retained Grid 1 and Focus with different trees after relaunch. It passed 8 additional grid switches and 12 app-tab switches with five apps remaining on the same Desktop and arrangement active. Closing Focus and Undoing restored it; Restore completed in one click without failures. GitHub Desktop accepted Changes input after restoration. The app was left open and paused with Grid 1 selected. See `acceptance-evidence/2026-10-18-workspace-tabs-final-universal.json`.

These checks verify transition selection, transparency, timer cleanup, real native switching, and storage. They do not independently certify every intermediate desktop video frame, Screen Recording-enabled preview animation, or physical multi-display switching.

## Version 0.2.3 grid editing — 2026-10-18

The Trellis website guide and the installed app's bundled interactive lessons were reviewed for docking, tabbing, seam resizing, and focus/return behavior. The installed Trellis process did not expose a usable native workspace in this session; this is not a claim of complete native reference-app testing. No proprietary implementation or assets were copied. Canopy continues to omit the Desktop grid tile as requested.

Actual mouse tests in Canopy's 1160 × 760 inspector exercised sidebar-to-center tabbing, tab-header tear-out to an edge, card-body docking while arrangement was active, a split inside a tab group, one-step Undo/Redo, and double-click focus/return starting from Everything. Recursive clipping prevents a card's intrinsic content from overlapping its neighbors. Compact cards retain accessible tab headers.

Native tests used Chrome, GitHub Desktop, System Settings, WhatsApp, Finder, and Muse across runs. Seam movement changed actual native geometry during the drag. GitHub Desktop rejected an undersized edit; Canopy restored the previous verified layout and stayed active. A subsequent edit clamped at its demonstrated 960-point width. Finder accepted Applications navigation after native tab editing. Off-Desktop Obsidian remained excluded.

Muse changed from onboarding to a new main native window during testing. Direct native-ID resolution distinguished the new window from obsolete AX references and replaced fragile frame inference. One earlier test baseline was transferred from the obsolete onboarding entry to the confirmed main window in backed-up Canopy state; Recover Windows restored the main window to 1200 × 800, independently confirmed by its native screenshot dimensions. This repair changed only Canopy's recovery metadata. Two older unresolved recovery baselines remain preserved.

A final development close-and-immediate-Restore run removed Finder from the grid and restored the other five native apps exactly to their captured original frames. A late closure notification left a stale failure banner even after recovery completed; that message race was then fixed with a regression test. Final universal-build acceptance is recorded separately in `acceptance-evidence/2026-10-18-editor-final-universal.json`.

The final universal 0.2.3 build 7 retained Accessibility access, arranged the five current-Desktop apps, accepted physical sidebar-to-center Finder tab docking, and completed double-click focus/return. GitHub Desktop accepted a Changes click while arranged. Closing the disposable Finder window and immediately pressing Restore completed in one click, with no current-session recovery entries and no stale failure banner. Native screenshot dimensions independently confirmed GitHub Desktop returned to 1277 × 734 and Muse to 1200 × 800. Canopy was left open and paused; the two earlier unresolved baselines were preserved.

Optional `_AXUIElementGetWindow` SPI is resolved dynamically, with unique exact-frame matching as the fallback. The direct path was tested on macOS 26.2. Future macOS compatibility and fallback behavior on a system without that SPI remain unverified. Physical multiple displays, trackpad gestures, global titlebar docking/double-click behavior, preview fidelity, energy use, and notarization still require dedicated acceptance. These editor fixes do not certify every Trellis feature.

## Version 0.2.2 real-app regression run — 2026-10-18

- A first development run exercised Chrome, Finder, and TextEdit: actual input, zoom and return, cross-app tabs, split resizing and undo, view save/recall, and exact restore. The bridge recorded 26 requested/actual native frame pairs. See `acceptance-evidence/2026-10-18-real-apps.json`.
- The original-desktop retry found that old persisted chain layouts still allocated narrow/shallow cells, System Settings caps its width, and nearest-window/default-visible matching included apps on other Desktops. Those defects were fixed and the retry used confirmed current-Desktop windows only.
- Chrome, GitHub Desktop, System Settings, and WhatsApp arranged with no Desktop cell. Off-Desktop Obsidian was absent from live panes and native writes. Chrome accepted text in a disposable local data-URL page; GitHub accepted Changes/History clicks in grid, zoom, and a native cross-app tab group. Undo returned to the grid.
- A newly created Chrome window was enrolled and closed. The live count returned from five to four; its saved record, pane, and restoration journal entry were absent. Restore then completed in one click with no session windows left to restore.
- All four remaining windows exactly matched their pre-test native frames after restoration. System Settings remained narrower than its allocated cell during arrangement; that is accepted because it stays within the cell. Oversized or displaced windows still trigger rollback.
- Tests also cover current-Desktop-only writes, unavailable saved views, transient empty visibility during Space animation, and closure cleanup without AX destroy notifications. The live runs encountered Space changes and conservatively paused; they do not certify every macOS Spaces or multi-monitor configuration.
- Two older unresolved recovery baselines from the earlier failure are preserved rather than discarded. These are separate from the successful current-session restore. Workspace backups were created before removing our own closed test records and saved test view.

Final universal 0.2.2 build 5 was opened at the canonical path, retained Accessibility, arranged four current-Desktop apps with no Desktop/Obsidian pane, accepted a GitHub Changes click, remained active after settling, and restored in one click. It is left open and paused. Binary hash and smoke results: `acceptance-evidence/2026-10-18-final-universal.json`.

Current-desktop native measurements are in `acceptance-evidence/2026-10-18-current-desktop.json`. Title-bar drag docking, trackpad gestures, previews, physical multiple displays, launch-at-login, energy profiling, and Developer ID notarization still need dedicated acceptance.

## Native results — 2026-10-18

- Discovery: exactly three disposable windows, including two identical titles; stable identifiers reconnect after helper relaunch.
- Arrangement: fixture 0 at (1293, 38), 1277 × 924; fixture 1 at (2578, 38), 854 × 1394; fixture 2 at (8, 970), 2562 × 462. These are exports of actual NSWindow frames.
- Native tab creation: fixture 0 became visible at (8, 66), 3424 × 1366, leaving the 28-point tab strip. The other two were minimized. Native tab switching still needs an uninterrupted dedicated pass.
- Final-build smoke: focus, return to Everything, save/recall view 1, accessible split adjustment, and undo completed with all three identities retained and no premature resize warning.
- Exact restoration: after focus and saved-view cycles, all three frame, title, visibility, and minimized-state records exactly matched the original JSON baseline. Relaunching Canopy, then entering real mode, loaded the layout and saved view while remaining paused; a fresh export still exactly matched baseline.
- Space handling: changing macOS Spaces paused arrangement and displayed the expected explanation. Launch the helper after activating the workspace on the same Desktop; otherwise app activation can itself switch Spaces and interrupt the test.
- Cleanup: Canopy was left paused with no windows left to restore. The disposable helper was closed.

The fixture needed explicit public Accessibility frame/minimized getters and setters: inherited bare-NSWindow behavior accepted requests without reliably reflecting them in its actual window. These controlled fixture results validate Canopy's requested geometry and workflow, not compatibility with every application's AX implementation.

The live run found and fixed three main-app defects: minimized/off-Space elements could disappear from discovery; Dock animation readbacks could lose minimization ownership and produce premature resize warnings; missing windows could be treated as successfully restored. The bridge now retains valid omitted elements, tracks acknowledged minimize requests through animation, verifies/retries placement after settling, and leaves missing restores retryable. Three new automated regressions cover preserved baselines, settled verification/persistent failure reporting, and retryable restoration.

At that fixture stage, third-party app behavior remained unverified. The later 0.2.2 runs above provide the current evidence; tear-off, title-bar docking, previews, physical multiple displays, gestures, login registration, energy profiling, and notarization remain open.

## Full-app launch correction — 2026-10-18

The user's Use My Windows report was traced to the still-running fixture-only instance at `dist/Canopy.app`: the click entered real mode, but its bundle filter correctly exposed zero personal-app windows. The normal and test bundles shared an identifier, allowing macOS to reuse the test instance for a full-app launch. The test instance was quit and the full release opened, without arranging personal windows. The canonical `dist/Canopy.app` now matches the full release executable exactly.

The test script now emits `dist/test/Canopy Test.app` with identifier `org.canopywm.Canopy.Test` and no normal URL registration. Its signature and fixture restriction were verified. The install script's rejection of a fixture-only source was exercised before the canonical bundle was replaced. After the user approved system authentication, the full build reported Accessibility Enabled. Clicking Use My Windows discovered 4 available windows, enabled Arrange Windows, and showed “Paused · layout changes stay in Canopy.” Personal windows were not arranged during this check.

## Real-app arrangement failure and recovery — 2026-10-18

After the user pressed Arrange Windows, large miniature panels covered Chrome and WhatsApp, and the Desktop plane itself used a full-pane interactive overlay. Miniatures required a double-click. Resize verification also incorrectly treated the app's retained frame as its minimum size, permitting a rejected resize to turn a usable app into a hidden window and large miniature.

Restore was invoked twice and reported three failures; quitting removed all overlays and left no manager-owned minimized windows. GitHub Desktop accepted a History click and a return to Changes. Chrome's normal window and page controls were accessible again. The persisted recovery journal retained two original-frame entries; exact restoration of all personal-window geometry is not certified.

Version 0.2.1 removes minimum-size inference from rejected writes, restores and pauses after settled resize failure, and checks that active windows fit before initial arrangement. The Desktop overlay is limited to 120 × 32 points, and miniature/Desktop buttons respond to one click. New automated regressions verify rollback and overlay removal, no native writes/minimization for cramped initial layouts, ordinary-click activation, and Desktop control bounds. These tests do not substitute for a new third-party native acceptance run. Canopy was left stopped during recovery.

## Demo

Open `dist/Canopy.app --args --demo` using `open`. Confirm the whole workspace renders at its default 1160 × 760 size and at 850 × 560. Capture it on an unlocked Mac. Check light and dark appearance, keyboard focus, and Reduce Motion.

- Confirm four sample windows appear across three leaves, with Browser and Notes in one tab group.
- Select Notes; drag it to a leaf edge to tear it out, and into the center to tab it again.
- Resize both seams and verify undo/redo.
- Zoom into a window and a nested space, then navigate with breadcrumbs and history.
- Save and recall a view through both the sidebar and keyboard shortcuts.
- Confirm all demo commands leave real windows untouched and do not create a workspace file.

## Real windows

Enable Accessibility manually after clicking Use My Windows. Start with the scoped CanopyFixture session, then explicitly choose third-party disposable windows for broader application compatibility testing.

- Quit before arranging; confirm no window moves.
- Arrange; compare visible native frames with the tree. Verify minimum-size failures are reported.
- Dock and float one window; confirm floating restores its pre-arrangement frame.
- Tab windows from different apps; select each tab and confirm native stacking order.
- Minimize a managed window, verify neighbor reflow, then restore it and verify its tree position.
- Close a managed window, then undo a layout edit; verify the closed window does not reappear as a ghost.
- Restore All; verify every moved window returns to its baseline, even after multiple focus changes.
- Relaunch; verify the layout loads while the desktop remains paused.

## Multiple displays

- Connect two displays, including a display left of or above the primary.
- Arrange windows on each display and verify menu bar/Dock insets.
- Dock a sidebar window into the other display's tree; confirm it appears exactly once.
- Save a different view on each display and verify each recalls independently.
- Disconnect one display while arranging, then restore; confirm no restored window is stranded offscreen.

## Permissions and storage

- Revoke Accessibility during an active arrangement; confirm Canopy reports it and stops applying frames.
- Re-enable permission and retry Restore; confirm failed windows remain retryable.
- Exclude an app; confirm it is restored and no longer enrolled. Include it again; confirm it stays floating.
- Validate URL commands against the packaged app.
- Confirm workspace data stays local and Screen Recording is requested only after the user opts into window previews.

Record OS, toolchain, apps, display topology, actual observations, and valid captures alongside the results. A build or fake-bridge test is not a substitute for these checks.
