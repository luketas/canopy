# README artwork

The app icon is unchanged. `canopy-icon.png` is a copy of the existing 512-pixel icon rendered by [make-icon.swift](../../scripts/make-icon.swift); this original icon is also used by the app bundle.

The feature illustrations were generated on October 19, 2026 with the built-in OpenAI image generation tool through the imagegen skill. They are explanatory illustrations, not native app screenshots. They contain no captured user windows or personal data. Final PNG outputs are included here and referenced directly by the repository README.

| Asset | Purpose |
| --- | --- |
| [canopy-icon.png](canopy-icon.png) | Existing app icon, retained without modification |
| [workspace-grids.png](workspace-grids.png) | Independent workspace tabs and 2–4 column arrangements |
| [drag-to-dock.png](drag-to-dock.png) | Empty-slot fills, nested splits, and center tabs |

The final prompts are preserved below. No CLI fallback was used.

## Workspace grids prompt

```text
Use case: ui-mockup
Asset type: wide GitHub README feature illustration for Canopy, an open source native macOS window manager.
Primary request: Explain independent workspace grids with different apps and different column arrangements in one refined product illustration. This is an explanatory illustration, not a screenshot.
Composition: wide landscape, about 2:1, warm ivory backdrop. Three equally sized crisp front-facing desktop panels across the image. Each panel has a slim native workspace tab strip at the top labeled exactly "Focus", "Build", "Plan"; highlight Focus on first panel, Build on second, Plan on third. First desktop: two columns, one tall writing window left, two stacked reference windows right. Second desktop: three tall columns for a code editor, browser, terminal. Third desktop: four columns with a calendar, tasks, notes, and files, two of them split vertically. Each window has restrained macOS-like charcoal title chrome and three tiny traffic-light dots. Window contents are abstract readable visual motifs, no personal data. Below the three desktops, captions exactly "Two columns", "Three columns", "Four columns".
Style: immaculate native macOS product illustration, precise geometry, subtle soft shadows, rounded corners, flat forest green #2F765E, pale sage, slate blue and warm ochre accent surfaces; generous whitespace, clean system sans typography. Keep all UI large and readable. White and ivory surfaces with fine gray dividers, limited color. No photo, no laptop hardware, no perspective distortion, no textures, no decorative plants, no invented logo. Do not draw or redesign the Canopy icon. No Trellis assets or branding, no watermark.
```

## Drag-to-dock prompt

```text
Use case: infographic-diagram
Asset type: wide GitHub README feature illustration for Canopy, an open source native macOS window manager.
Primary request: Make an elegant three-panel visual guide to docking a floating app window: filling an empty grid slot, creating a new split, and joining a slot as a tab.
Composition: wide 2:1 landscape, warm ivory background, three clear equal-width panels with generous whitespace. Large exact headings above them: "Fill a slot", "Split a slot", "Add a tab". Each panel contains a front-facing simplified native desktop window grid. Dark charcoal window title bars with three tiny traffic-light dots, forest green #2F765E and sage accents, soft ivory app contents, fine gray borders, restrained soft shadows.
First panel: a two-column desktop, writing app on left, empty right slot with a fine dashed outline. A smaller floating ochre notes window overlaps right slot, a single arrow points into it, entire empty right slot softly highlighted sage green. One black pointer on floating titlebar.
Second panel: a two-column desktop, full-height writing app left, reference app top-right, floating ochre notes app being dropped at lower edge of right-hand slot. Only bottom half of right column highlighted sage with a clear horizontal new division. A small downward arrow indicates the edge docking.
Third panel: one large app pane with an actual tab strip containing exactly two tabs "Browser" and "Notes". Notes tab highlighted green. A small floating ochre notes window with arrow points to the center of the pane, so it joins as a tab rather than creating a new division.
Style: polished editorial macOS product illustration, systematic precise geometry, entirely flat front-facing UI, readable system sans type, schematic contents with abstract text lines only. No real app brands, personal data, Canopy icon, Trellis branding, hardware, textures, photo, perspective distortion or watermark. No extra captions or text beyond the specified headings and tab labels.
```
