---
name: Canopy
description: Native macOS workspace inspection and explicit window arrangement.
colors:
  forest-light: "rgb(16% 40% 30%)"
  forest-dark: "rgb(43% 73% 57%)"
rounded:
  compact: "5px"
  tab: "6px"
  tile: "10px"
spacing:
  header: "20px"
  canvas: "24px"
  seam: "10px"
components:
  column-count:
    rounded: "{rounded.compact}"
    width: "28px"
    height: "26px"
  column-header:
    rounded: "{rounded.compact}"
    height: "28px"
  desktop-workspaces:
    height: "32px"
  window-tile:
    rounded: "{rounded.tile}"
    padding: "{spacing.header}"
---

# Design System: Canopy

## Overview

**Creative North Star: "Native workspace inspector"**

Canopy is a compact SwiftUI/AppKit macOS utility. System typography, SF Symbols, real application icons, native menus, and restrained forest-green selection support direct workspace editing. The canvas explains the window arrangement; the desktop strip keeps workspace navigation available when the editor is closed. Extend these existing conventions incrementally.

**Key Characteristics:**

- Native utility chrome and compact controls.
- Visible membership, column structure, and selected workspace.
- Neutral surfaces with restrained accent and app-color cues.
- Explicit window movement, reversible edits, and honest status labels.

This implementation-derived record was refreshed on 2026-10-18. The independent [columns UI review](docs/acceptance-evidence/2026-10-18-columns-ui-review.md) returned **ship** for the visible editor at 1160 × 760 and 850 × 612, and the editor-independent 3440 × 32 desktop strip. Empty-column appearance was absent from that inspection; its description below comes from code. Fresh CUA tool images were the review evidence; no screenshot files were saved. No approved comp was supplied, and no web detector ran for this native surface. Earlier scoped reviews covered clipping, primary-action labels, Desktop representation, and minimum-size toolbar visibility. Functional evidence, including the separate 114-test result and real native-window observations, lives in [acceptance.md](docs/acceptance.md); this visual verdict does not certify those behaviors or complete accessibility coverage.

## Colors

The editor's primary tint is adaptive forest green, with separate light and dark values in the frontmatter. Native semantic colors own window, control, canvas, text, separator, and disabled states; do not freeze them to a light-mode screenshot. The desktop strip uses AppKit's system control accent for its selected fill.

App-tinted leaf bodies remain subtle: editor/code blue, browser green, terminal purple, and warm brown for other apps. These identity cues sit behind content. Selection and drop feedback use translucent accent fills and thin outlines. `Palette` in `Sources/Canopy/WorkspaceView.swift` owns the adaptive editor colors.

## Typography

Use the macOS system font and semantic SwiftUI text styles. Grid/sidebar headings use title2 semibold; supporting explanations use callout. Sidebar app names use callout medium, while window titles and other-grid annotations use caption and caption2 with one-line limits. Expanded tiles use headline app names and caption titles limited to two lines. Column labels use caption semibold; count choices use callout medium.

The native desktop strip uses a 12-point system font, regular for workspace buttons and semibold for the selected workspace; Edit Grids uses medium. Preserve text-and-icon primary toolbar labels and SF Symbols.

## Layout

The workspace window uses a navigation split view with a 210–310 point sidebar (236 ideal), toolbar, workspace tabs, heading and column controls, recursive canvas, and status footer. Its default total size is 1160 × 760 points. The content constraint is 850 × 560; the observed attainable total minimum is **850 × 612**, including native chrome. Preserve visible Columns 1/2/3/4 choices and Apply Grid at that minimum.

Header/tile insets, canvas inset, and seam size use the frontmatter roles. Seams have a small grip. The separately adjustable native window gap ranges from 0–32 points. The sidebar stays bounded to its measured height: fixed heading/search above a scrolling list, fixed removal target/help below.

Explicit columns compose side by side, with vertical stacks inside each. Every column has a labeled header, including empty columns. Presets retain full-column drop slots when there are fewer leaf groups than columns. Tiles below 220 points wide or 240 high use app icons; app tabs remain visible at 160 points wide and 80 high or larger. Nested spaces below 140 points wide or 100 high collapse to a group summary.

**The Reserved Strip Rule.** While arrangement is active, place the workspace strip across each display below the menu bar and reserve its height before positioning app frames. In the observed 3440-wide display it occupied (0, 30, 3440, 32); app content began at y=70 with the current gap. These coordinates describe that display, not a universal menu-bar height. Tabs belong to each display's workspaces. Physical multiple-display behavior remains outside the recorded acceptance.

## Elevation & Depth

Standard macOS surfaces, tonal layering, and thin separators establish hierarchy. Avoid decorative card shadows. Transparent, nonactivating desktop overlay panels have no custom shadow. Selected fills, drop previews, and seam grips communicate interaction.

Inspector focus transitions use 220ms. Native camera transitions use 460ms and schedule timers only while animating. Both respect Reduce Motion. Direct seam and docking edits apply native frames without a camera transition.

## Shapes

Use the compact, tab, and tile corner roles in the frontmatter. Tile outlines promote from a thin border to 2 points for selection or a drop target. Empty columns share the tile silhouette with a 1-point dashed outline (5-point dash, 4-point gap). Native buttons, text fields, and menus keep platform shapes.

## Components

### Toolbar and status

The primary action is **Use My Windows** in demo mode and **Apply Grid** for real windows, retaining icon and text. Apply Grid applies chosen membership and is disabled without Accessibility permission or membership. **Restore Windows** remains available after an unsuccessful restore. **Recover Interrupted Session** belongs in File and menu-bar menus, with recovery also in Workspace settings; preserve toolbar room for Apply Grid.

Demo and fixture modes are labeled. Real-window mode starts paused, and the footer distinguishes paused editing from active arrangement. A dismissible inline message explains permission, storage, or frame-application problems. Optional in-memory still previews are separate from native movement.

### Workspace navigation

Editor workspace tabs scroll horizontally, showing names, membership counts, and restrained selected fills. **New Grid** creates and selects an empty grid. Context menus offer Duplicate Grid, rename, and close; the last grid cannot close. Desktop is excluded from membership: do not add a Desktop grid tile.

The native **Canopy Workspaces** strip works with the editor closed. Per-display workspace-name buttons expose selected state, and **Edit Grids** reopens the editor. Keep panels and native buttons stable during ordinary switches; refresh state rather than recreating controls on each layout update. Rebuild buttons when workspace identities or names change. Tab widths adapt between 36 and 180 points, reserving 110 points for Edit Grids. Selected tabs use subdued system-accent fill and semibold text.

### Membership controls

**Find a window** searches app names and titles without regard to case. The sidebar separates **In [grid name] · [count]** from **Available windows**. Plus/minus actions add or remove membership; available rows annotate other grids. **Add All** adds filtered available windows; an empty grid offers **Add All Available Windows**. Exclude Desktop and unavailable windows, including windows on other Spaces.

Sidebar minus, app-tab x, context menu, Place Window menu, and **Drop here to remove** remove only current-grid membership, keeping the app open. Undo restores membership. Dropping onto another workspace tab transfers the window and selects the destination. Explicit-column additions fill empty columns first, then the least-populated column; other automatic additions balance leaf groups. Edits persist while paused and update managed frames while arranging. Removal restores a newly floating managed window where possible.

### Columns and placement

**Columns 1/2/3/4** sits directly below the grid title and count. Adjoining count buttons share a subdued container, with accent fill for the chosen count. Presets redistribute leaf groups into vertical stacks and preserve empty-column slots.

Each **Column N** header has a split/stack SF Symbol and help identifying it as a stack target. Dropping on the header stacks a window vertically; active targeting displays **Stack in this column**. An empty column says **Drop a window** and **Use this full column**, with a plus-window symbol and dashed border. This empty appearance is implementation-documented and was not present in the fresh visual review.

**Give Own Column** appears in window context menus and **Place Window**. Left/right drops beside explicit columns create adjacent full columns; top/bottom drops stack, and a leaf's center creates tabs. Edge targeting uses the nearest outer 24%. Place Window also offers Stack in Column, Stack Above, and Stack Below for the selected window. Preserve native menu paths alongside dragging.

### Canvas navigation

Seam drags resize the canvas continuously and apply native frames at completion; seam controls expose accessibility adjustments. Double-click and expand focus a leaf; breadcrumbs navigate outward. Saved-view slots save when empty and recall when filled, with context-menu overwrite. Undo edits layout; history navigates the camera. Native overlays provide app tabs, grips, docking previews, compact group tiles, and camera controls. Inactive managed tabs are minimized with ownership recorded so restore preserves windows minimized independently.

## Do's and Don'ts

### Do:

- Do preserve system typography, SF Symbols, native menus, and adaptive semantic surfaces.
- Do keep column choices, labeled stack targets, selected workspaces, and Apply Grid readable at the attainable minimum.
- Do reserve the desktop strip before calculating managed app frames and keep Edit Grids available when the editor closes.
- Do distinguish source-derived states, scoped visual review, and real native-window acceptance.

### Don't:

- Don't replace native controls with web-style chrome or invent a new visual identity for an incremental editor change.
- Don't add Desktop as a grid tile or membership choice.
- Don't recreate desktop workspace buttons during ordinary selection updates.
- Don't describe 850 × 560 as the minimum total window or claim screenshots were saved when only CUA tool images were observed.


Workspace switching changes native stacking order without minimizing/restoring apps, capturing the screen, or waiting on an animation. Inactive windows stay live behind a normal-level background; active windows and floating apps remain above it. Empty-area clicks stop at that background. Reuse unchanged native frames; first placements and actual layout changes can still write geometry. Workspace canvases swap identity without morphing. Optional zoom/layout animation remains separate. Global workspace cycling uses Option–Tab / Option–Shift–Tab; direct selection uses Control–Option–Command + 1–9; pane shortcuts retain Control–Option + arrows. Settings distinguishes the two scopes. Control–Option–A arranges only the current Desktop windows on the monitor under the pointer: two side by side, four in a 2×2 grid.

During seam resizing, preserve window stacking and update only geometry. Keep native seam controls under the pointer by measuring deltas from the original seam. Coalesce intermediate writes, flush on release, and treat the drag as one undoable edit. Floating title-bar drags need no modifier: preview empty-slot fills, edge splits, center tabs, and screen-edge splits beside the whole grid. Keep a single preview surface alive through the drag and accept docking only after actual native window movement.
