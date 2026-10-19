# Canopy

<!-- impeccable:product-schema 1 -->

## Platform
Native macOS, minimum macOS 14. Universal arm64 and x86_64 builds compile; live testing currently uses Apple silicon.

## Stack
Swift, AppKit, SwiftUI, Accessibility, Carbon hotkeys, Swift Package Manager.
Assumption for this initial build: native macOS is the intended platform because the supplied reference is a Mac window manager.

## Product Purpose
Build an independent open source version of the nested, zoomable desktop workflow demonstrated at https://trelliswm.app/.

## Users
Assumption: Mac users working across several applications who want related windows grouped into navigable spaces.

## Operating Context
A menu bar utility with a workspace inspector. Window management starts only after an explicit Arrange action. A demo works without Accessibility permission.

## Capabilities and Constraints
The implementation includes nested splits and tabs, per-display trees, continuous camera navigation, native desktop docking and tab strips, miniature tiles, optional ScreenCaptureKit still previews, saved views, history, undo, exclusions, configurable shortcuts, URL commands, and window restoration. Public gesture monitors are passive, so the first event can also reach the original app; exclusive Overview offers direct camera control. Native application minimum dimensions are respected. Persistent identities use bundle, title, occurrence, document, Accessibility identifier, and geometry with ambiguous matches rejected.

## Brand Commitments
Canopy is a provisional name. The MIT license is an initial implementation choice; neither the name nor license has been confirmed by the user. Independent branding and code; the Trellis product remains the behavioral reference.

## Evidence on Hand
The live TrellisWM site and its how-it-works page were read on 2026-10-14. The repository contains source, tests, a native bundle script, and an interactive demo. Demo window titles and contents are synthetic.

## Product Principles
- Window movement is explicit and reversible.
- Preserve the nested workspace when zooming.
- Use public macOS APIs without disabling system protections.
- Explain missing permissions and unsuccessful moves.
- Keep the layout engine independently testable.

## Open Decisions
Final product name, license, platform expansion, publishing destination, and distribution signing credentials.
