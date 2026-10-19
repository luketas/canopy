# Architecture

Canopy separates a deterministic layout model, public macOS window operations, and desktop presentation.

## Model

A LayoutNode is a leaf of windows/tabs, an explicit empty column, or a binary split with an ID, axis, and ratio. Moves validate destinations before extracting a window or whole group. Removal collapses redundant splits. Decoding rejects duplicate window/node IDs and malformed branches. Geometry partitions top-left rectangles without negative sizes. Minimized or dormant branches yield space while retaining their structure.

Each display uses a persistent display UUID and owns workspace tabs. Every tab has its own tree, focused node, optional free camera rectangle, nine saved views, and bounded navigation history. Free rectangles participate in history. Structural undo is separate. Display descriptors and window bridges are injectable, making tests independent of a physical desktop.

CameraViewport projects logical geometry into a viewport, preserves the point under a pinch, constrains zoom/pan, and supports rectangle framing. DockResolver prioritizes screen edges, then leaf edges/centers. Source IDs survive moves unless the source leaves behind an explicit empty column with that identity. Detached moving nodes receive new IDs to avoid collisions. Column markers preserve full-height membership; balanced horizontal splits compose columns, and vertical splits stack their windows. Empty columns reserve geometry without creating window records.

## Native placement

DesktopPlan computes placements, native active-window frames, miniatures, tab-strip insets, and seam hit regions. Application-enforced minimum sizes are learned from readback. Tiny groups collapse to one miniature. The Desktop shortcut returns to floating windows without reserving a grid tile. Explicit column widths adapt to demonstrated native minimums if the display has enough room.

Active, fully visible, large-enough windows are raised above a normal-level, nonactivating workspace background. Inactive tabs, off-camera windows, and miniature windows stay live below it; user-minimized windows are excluded. Workspace switches never minimize apps. Per-window target caching plus actual frame readback skips unchanged geometry; a changed target or manually displaced app is placed again. Legacy minimization ownership remains for restoration only. Original frames are persisted before the first mutation. Native frames are read back after changed position/size writes; a corrective position write follows only if needed. Failed restores remain retryable.

Live resize coalesces updates with a 60 Hz timer in common run-loop modes. When native membership is unchanged, placement updates geometry without activation, raising, background restacking, transitions, or intermediate persistence. Existing seam/tab/miniature panels follow the new frames. Mouse-up flushes the latest ratio and commits one undoable edit. Participating apps' AXEnhancedUserInterface flags are temporarily disabled if originally enabled and restored when the resize ends or is cancelled.

## macOS integration

NSWorkspace supplies regular applications. Accessibility supplies standard windows, identifiers, document hints, frames, minimization, and fullscreen state. Within a session, AX element equality preserves IDs. Reconnection uses scored fingerprints and refuses ties. WindowServer confirms native IDs on the current Desktop. Optional runtime `_AXUIElementGetWindow` SPI resolves AX IDs directly; a unique exact-frame match is the fallback. ScreenCaptureKit uses those IDs. No SIP changes are needed; the optional SPI path may change on future macOS versions.

AXObserver notifications drive discovery, focus, geometry, minimization, and destruction updates. App lifecycle notifications reconnect dormant apps; a 15-second watchdog covers incomplete AX implementations. A 150ms per-element timeout bounds individual AX calls. Fullscreen windows are unavailable. Active Space changes pause arrangement to avoid crossing macOS desktops implicitly.

AX coordinates have a top-left origin; NSScreen coordinates have a bottom-left origin. Conversion uses the primary screen top and supports negative secondary-display positions. Visible frames preserve menu bar and Dock insets.

## Desktop presentation

Nonactivating NSPanels provide workspace tabs below the menu bar, app-tab strips, seams, miniatures, and docking feedback. Workspace panels and native buttons remain alive across layout updates; per-layout controls are rebuilt separately. DesktopPlan reserves the workspace strip’s 32-point height above native app frames. Edit Grids routes through SwiftUI’s openWindow action. They are transient and stay out of window cycling. Gesture and title-bar monitors observe public NSEvents. Initial global events cannot be consumed retroactively; exclusive interaction starts once the camera overlay is open.

Floating title-bar drags use WindowServer event coordinates and source-window stacking order. A common-mode timer follows actual native movement while the owning app handles its drag loop; toolbar clicks without window movement cannot trigger docking. Floating windows bypass the optional Option requirement for already-managed windows. One reusable preview panel follows the resolved slot/edge. Empty grids use a nonpersistent spacer target rather than creating a Desktop window record.

Workspace switches apply synchronously without a capture or settling deadline. The coordinator orders a cached wallpaper surface above inactive windows, activates the selected native app before raising companion windows, and positions its own surface below the backmost active window. A generation-guarded restacking monitor runs for 300 ms after applying, handling queued activation restacks without moving apps or delaying input. A runtime-resolved SkyLight transaction orders only Canopy's own surface; AppKit ordering is the fallback. This optional SPI may change on future macOS releases and needs no SIP changes. The surface accepts empty-area clicks but never keyboard focus. Background images decode off the main thread at bounded resolution. Workspace canvases swap identity without morphing. Carbon and AppKit shortcut events share timestamp deduplication.

The camera renders the tree from still previews or app icons, with continuous pointer zoom, pan, and framing. On settle it hands control back to native placements. Layout transitions interpolate frames over 460ms, honor Reduce Motion, and use timers only while moving. Preview capture is opt-in, bounded, and stops when neither arrangement nor inspector needs it.

## Storage and commands

Schema 4 reads schemas 1–3 and stores workspace tabs, explicit columns, preferences, camera locations, dormant entries, and a restoration journal. Writes are atomic. Unknown or corrupt files are preserved. Import validates, restores the old session, creates a backup, and starts paused. Export excludes the active journal. SIGTERM/SIGINT request graceful shutdown; crash recovery is explicit after relaunch.

Carbon hotkeys and registered Apple Event URLs invoke the same store commands as the UI. Shortcuts are configurable and conflicts are reported. Login registration uses SMAppService. The app has no network service, account, payment layer, recording pipeline, or telemetry.

Fixture mode restricts the real bridge to a disposable bundle and uses separate storage. Automated tests use fake bridges; the native fixture exports its own frames for live comparison.
