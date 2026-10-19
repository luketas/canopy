# Complete macOS implementation

Implementation coverage is listed separately from native acceptance. See [acceptance results](acceptance.md) for measured behavior and remaining verification.

- [x] Public-API ScreenCaptureKit in-memory previews, permission opt-in, bounded cache.
- [x] Desktop title-bar docking, edge/center preview, cross-display moves, tab-group tear-off.
- [x] Desktop workspace tabs, app-tab strips, split seam controls, miniature tiles.
- [x] Per-workspace app membership, 1–4 column presets, drag stacking, own-column placement, empty drop slots, and Undo.
- [x] Continuous camera, pointer zoom, rectangle framing, animated transitions, off-camera policy.
- [x] AXObserver discovery, app lifecycle, reduced polling, paused/dormant/fullscreen handling.
- [x] Richer matching, reconnect absent apps, crash journal/recovery, corrupt-state backup/reset.
- [x] Configurable shortcuts, start at login, import/export, keyboard docking, permission onboarding.
- [x] Universal packaging, signing/notarization commands, CI artifacts, install/uninstall guidance.
- [x] Automated regressions and controlled native fixture.
- [ ] Complete native acceptance, including permission-dependent window moves and physical multiple displays. See acceptance.md for observations rather than inferring verification from implementation.
