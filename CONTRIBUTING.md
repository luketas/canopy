# Contributing

Canopy is a small native macOS project with no external package dependencies. Use Swift 6 and macOS 14 or newer.

```sh
swift test
bash scripts/build-app.sh
open dist/Canopy.app --args --demo
```

Tree algorithms live in `CanopyCore`; keep them independent of AppKit. Add regression tests for window conservation, geometry, view IDs, and persistence when changing the model. Workspace tests use an injected fake Accessibility bridge and temporary storage; they must never move actual desktop windows or write to the user's Application Support directory.

Changes to the macOS bridge need a documented manual acceptance run. Include the OS version, apps used, permission state, display topology, and observed restoration behavior. Never assume a successful AX return means the app accepted the requested frame; read it back.

Keep window movement explicit. Demo mode, inspection, paused edits, and quitting a never-active session must not move windows. Always preserve the original frame before moving a window, and keep failed restores retryable. Preserve unreadable or newer-version workspace files.

The UI uses system controls, SF Symbols, and adaptive macOS colors. Respect Reduce Motion and keyboard accessibility. Label sample content, and request Screen Recording only when an explicit preview feature needs it.

Submit focused pull requests describing the changed behavior and checks performed. Contributions are under the repository's MIT license.
