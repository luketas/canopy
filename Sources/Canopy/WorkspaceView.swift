/*
THESIS: Make each grid’s window membership visible and directly editable.
OWN-WORLD: macOS utility chrome, system typography, restrained forest-green selection,
neutral canvas and app-colored leaves. The user supplied TrellisWM as the behavioral reference.
STORY: Start an empty grid, add chosen windows, drag to split or tab, remove without quitting apps.
FIRST VIEWPORT: Top grid tabs with counts; a searchable sidebar separates included and available windows.
Visible add/remove controls and a removal drop zone surround the recursive canvas. Apply Grid uses chosen windows.
FORM: Native macOS workspace inspector, constrained by the supplied reference and platform conventions.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
*/
import SwiftUI
import CanopyCore

private enum Palette {
    static let accent = adaptive(light: (0.16, 0.40, 0.30), dark: (0.43, 0.73, 0.57))
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    static func tint(_ record: WindowRecord?) -> Color {
        let name = record?.app.lowercased() ?? ""
        if name.contains("editor") || name.contains("code") { return adaptive(light: (0.21, 0.36, 0.57), dark: (0.48, 0.67, 0.90)) }
        if name.contains("browser") || name.contains("safari") || name.contains("chrome") { return adaptive(light: (0.16, 0.42, 0.34), dark: (0.43, 0.73, 0.57)) }
        if name.contains("terminal") { return adaptive(light: (0.40, 0.31, 0.53), dark: (0.71, 0.58, 0.87)) }
        return adaptive(light: (0.50, 0.36, 0.21), dark: (0.83, 0.67, 0.45))
    }
}

struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var windowSearch = ""
    @State private var showHelp = false
    @State private var renamingGrid: String?
    @State private var gridName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 310)
        } detail: {
            VStack(spacing: 0) {
                workspaceGridTabs
                Divider()
                workspaceHeader
                Divider()
                if let message = store.message {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { store.message = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }.padding(14).background(Color.accentColor.opacity(0.07))
                    Divider()
                }
                GeometryReader { geometry in
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)
                        if let node = store.visibleFocusedNode {
                            LayoutCanvas(node: node, store: store)
                                .padding(24)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: node.id)
                                .id(store.current?.activeGridID)
                                .transition(.identity)
                        } else { emptyWorkspace.background(EditorDropRegion(id: "empty",node: nil,store: store).allowsHitTesting(false)) }
                    }
                    .gesture(MagnificationGesture().onEnded { scale in
                        if scale > 1.15 { store.zoomIn() }
                        else if scale < 0.85 { store.zoomOut() }
                    })
                }
                Divider()
                HStack(spacing: 14) {
                    Label(store.isDemo ? "Demo · no real windows are moved" : store.isFixtureTesting ? "Fixture test · only disposable windows" : store.isArranging ? "Arranging your windows" : "Paused · layout changes stay in Canopy",
                          systemImage: store.isDemo ? "play.rectangle" : store.isArranging ? "circle.inset.filled" : "pause.circle")
                    Spacer()
                    Button("Shortcuts", systemImage: "keyboard") { showHelp.toggle() }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showHelp) { ShortcutHelp(store: store).padding(24) }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .tint(Palette.accent)
        .frame(minWidth: 850, minHeight: 560)
        .navigationTitle("Canopy")
        .alert("Rename Grid",isPresented: Binding(get: { renamingGrid != nil },set: { if !$0 { renamingGrid = nil } })) {
            TextField("Grid name",text: $gridName)
            Button("Cancel",role: .cancel) { renamingGrid = nil }
            Button("Save") {
                if let id = renamingGrid { store.renameWorkspaceGrid(id,name: gridName) }
                renamingGrid = nil
            }
        }

        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.navigateHistory(back: true) } label: { Image(systemName: "chevron.left") }
                    .disabled(!(store.current?.history.canGoBack ?? false)).help("Back")
                Button { store.navigateHistory(back: false) } label: { Image(systemName: "chevron.right") }
                    .disabled(!(store.current?.history.canGoForward ?? false)).help("Forward")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!store.canUndo).help("Undo layout change")
                Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!store.canRedo).help("Redo layout change")
                if store.isDemo {
                    Button("Use My Windows", systemImage: "macwindow") { store.useRealWindows() }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Restore Windows", systemImage: "arrow.counterclockwise") { store.floatAll() }
                        .labelStyle(.titleAndIcon)
                        .disabled(!store.hasWindowsToRestore)
                    Button("Apply Grid", systemImage: "rectangle.split.2x2") {
                        store.applyCurrentGrid()
                    }.labelStyle(.titleAndIcon).buttonStyle(.borderedProminent).disabled(!store.hasPermission || store.currentGridWindowIDs.isEmpty)
                }
            }
        }
    }

    private var workspaceGridTabs: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal,showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.current?.grids ?? []) { grid in
                        HStack(spacing: 6) {
                            Button { store.selectWorkspaceGrid(grid.id) } label: {
                                HStack(spacing: 7) {
                                    Label(grid.name,systemImage: "rectangle.split.2x2")
                                    Text("\(grid.root?.allWindows.filter { !WorkspaceStore.isDesktop($0) }.count ?? 0)").font(.caption).foregroundStyle(.secondary)
                                }
                                    .padding(.horizontal,10).padding(.vertical,8)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Workspace tab \(grid.name)")
                                .accessibilityValue(store.current?.activeGridID == grid.id ? "Selected" : "")
                            if (store.current?.grids.count ?? 0) > 1 {
                                Button { store.closeWorkspaceGrid(grid.id) } label: { Image(systemName: "xmark").font(.caption2) }
                                    .buttonStyle(.plain).padding(.trailing,10)
                                    .accessibilityLabel("Close grid \(grid.name)")
                            }
                        }
                        .background(store.editorDropTarget == "grid:\(grid.id)" ? Color.accentColor.opacity(0.25) : store.current?.activeGridID == grid.id ? Color.accentColor.opacity(0.12) : Color.clear,in: RoundedRectangle(cornerRadius: 6))
                        .background(EditorDropRegion(id: "grid:\(grid.id)",node: nil,gridID: grid.id,store: store).allowsHitTesting(false))
                        .contextMenu {
                            Button("Duplicate Grid") { store.selectWorkspaceGrid(grid.id); store.addWorkspaceGrid(duplicating: true) }
                            Button("Rename Grid…") { gridName = grid.name; renamingGrid = grid.id }
                            Button("Close Grid") { store.closeWorkspaceGrid(grid.id) }.disabled(store.current?.grids.count == 1)
                        }
                    }
                }
            }
            Button { store.addWorkspaceGrid() } label: { Label("New Grid",systemImage: "plus") }
                .buttonStyle(.borderless).disabled((store.current?.grids.count ?? 0) >= 32)
                .help("Create an empty grid and choose its apps")
        }.padding(.horizontal,20).padding(.vertical,8)
    }

    private var sidebar: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.split.2x2").font(.title2).foregroundStyle(Palette.accent)
                Text("Canopy").font(.title2.weight(.semibold))
                Spacer()
            }.padding(20)
            TextField("Find a window",text: $windowSearch)
                .textFieldStyle(.roundedBorder).padding(.horizontal,16).padding(.bottom,10)
                .accessibilityLabel("Find a window")
            List(selection: $store.selectedWindow) {
                Section("In \(store.currentGridName) · \(store.currentGridWindowIDs.count)") {
                    ForEach(filteredWindows(inGrid: true)) { record in windowRow(record,inGrid: true) }
                    if store.currentGridWindowIDs.isEmpty { Text("Drag a window into the grid to start.").font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(filteredWindows(inGrid: false)) { record in windowRow(record,inGrid: false) }
                    if filteredWindows(inGrid: false).isEmpty { Text(windowSearch.isEmpty ? "No other windows on this Desktop" : "No matching windows").font(.caption).foregroundStyle(.secondary) }
                } header: {
                    HStack {
                        Text("Available windows")
                        Spacer()
                        Button("Add All") { store.addWindowsToCurrentGrid(filteredWindows(inGrid: false).map(\.id)) }
                            .buttonStyle(.borderless).font(.caption)
                            .disabled(filteredWindows(inGrid: false).isEmpty)
                            .help("Add these windows to this grid")
                    }
                }
                Section("Saved views") {
                    ForEach(1...9, id: \.self) { slot in
                        let saved = store.current?.savedViews[String(slot)] != nil
                        HStack {
                            Button { if saved { store.recallView(slot) } else { store.saveView(slot) } } label: {
                                HStack {
                                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                                        .foregroundStyle(saved ? Palette.accent : Color.secondary)
                                    Text(saved ? "View \(slot)" : "Save view \(slot)")
                                        .foregroundStyle(saved ? Color.primary : Color.secondary)
                                    Spacer()
                                    if saved { Text("⌃⌥\(slot)").font(.caption).foregroundStyle(.secondary) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(store.focusedNode == nil)
                        }.padding(.vertical, 3)
                        .contextMenu {
                            Button("Save Current View Here") { store.saveView(slot) }
                            Button("Go to View") { store.recallView(slot) }.disabled(!saved)
                        }
                    }
                }
            }.listStyle(.sidebar).frame(minHeight: 0, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Drop here to remove",systemImage: "minus.circle")
                    .font(.callout.weight(.medium)).frame(maxWidth: .infinity,minHeight: 44)
                    .background(store.editorDropTarget == "remove-current-grid" ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08),in: RoundedRectangle(cornerRadius: 6))
                    .background(EditorDropRegion(id: "remove-current-grid",node: nil,removesWindow: true,store: store).allowsHitTesting(false))
                    .help("Drag a window here to remove it from this grid")
                Text("Drag into a card to split or tab. Drag onto another grid to move.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
                if !store.isDemo { Button("Open Demo") { store.enterDemo() }.buttonStyle(.link) }
            }.padding(16)
        }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func filteredWindows(inGrid: Bool) -> [WindowRecord] {
        store.listedRecords.filter {
            store.currentGridWindowIDs.contains($0.id) == inGrid &&
                (windowSearch.isEmpty || $0.app.localizedCaseInsensitiveContains(windowSearch) || $0.title.localizedCaseInsensitiveContains(windowSearch))
        }
    }
    private func otherGridNames(for key: String) -> String {
        store.current?.grids.filter { $0.id != store.current?.activeGridID && $0.root?.allWindows.contains(key) == true }.map(\.name).joined(separator: ", ") ?? ""
    }
    private func windowRow(_ record: WindowRecord,inGrid: Bool) -> some View {
        HStack(spacing: 8) {
            AppIcon(record: record,image: store.icon(record.id),size: 24)
            VStack(alignment: .leading,spacing: 3) {
                Text(record.app).font(.callout.weight(.medium)).lineLimit(1)
                Text(record.title.isEmpty ? "Untitled window" : record.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !inGrid,!otherGridNames(for: record.id).isEmpty {
                    Text("In \(otherGridNames(for: record.id))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                if inGrid { store.removeWindowFromCurrentGrid(record.id) }
                else { store.addWindowsToCurrentGrid([record.id]) }
            } label: { Image(systemName: inGrid ? "minus.circle" : "plus.circle").font(.body).frame(width: 28,height: 30) }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(inGrid ? "Remove" : "Add") \(record.app) \(inGrid ? "from" : "to") this grid")
                .help(inGrid ? "Remove from this grid; keep the app open" : "Add to this grid")
        }.padding(.vertical,4).tag(record.id)
            .overlay { WindowDragSource(key: record.id,label: record.app,store: store,excludedTrailingWidth: 32,onSelect: { store.selectedWindow = record.id },onOpen: { store.openWindow(record.id) }) }
            .contextMenu { windowActions(record) }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isDemo ? "A little room for everything." : store.currentGridName).font(.title2.weight(.semibold))
                    Text(store.isDemo ? "Try nesting, tabs, and zoom before arranging your desktop." : "\(store.currentGridWindowIDs.count) in this grid · \(store.availableRecords.count) on this Desktop")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if store.connectedDisplays.count > 1 {
                    Picker("Display", selection: $store.selectedDisplay) {
                        ForEach(store.connectedDisplays) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: 200)
                }
                Button("Everything", systemImage: "arrow.up.left.and.arrow.down.right") { store.showEverything() }
                    .disabled(store.focusedNode == nil)
                Menu("Place Window") {
                    if let key = store.selectedWindow {
                        Button("Give Own Column") { _ = store.giveWindowOwnColumn(key) }
                        if !store.gridColumns.isEmpty {
                            Menu("Stack in Column") {
                                ForEach(Array(store.gridColumns.enumerated()),id: \.element.id) { index,column in
                                    Button("Column \(index+1)") { store.stackWindow(key,inColumn: column.columnID!) }
                                }
                            }
                        }
                        Menu("Stack Above") {
                            ForEach(store.listedRecords.filter { store.currentGridWindowIDs.contains($0.id) && $0.id != key }) { target in
                                Button(target.app) { if let leaf = store.current?.root?.leaf(containing: target.id) { store.dock(key,target: leaf.id,edge: .top) } }
                            }
                        }
                        Menu("Stack Below") {
                            ForEach(store.listedRecords.filter { store.currentGridWindowIDs.contains($0.id) && $0.id != key }) { target in
                                Button(target.app) { if let leaf = store.current?.root?.leaf(containing: target.id) { store.dock(key,target: leaf.id,edge: .bottom) } }
                            }
                        }
                        Divider()
                    }
                    ForEach(DockEdge.allCases,id: \.rawValue) { edge in
                        Button(edge == .tab ? "Tab into Current Space" : "Dock \(edge.rawValue.capitalized)") {
                            if let key = store.selectedWindow { store.dock(key,target: store.focusedNode?.id,edge: edge) }
                        }.disabled(edge == .tab && store.focusedNode?.isLeaf != true)
                    }
                    Button("Remove from This Grid") { if let key = store.selectedWindow { store.removeWindowFromCurrentGrid(key) } }
                }.disabled(store.selectedWindow == nil)
                if store.isArranging { Button("Overview",systemImage: "viewfinder") { store.onRequestCamera?() } }
            }
            HStack(spacing: 8) {
                Text("Columns").foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(1...4,id: \.self) { count in
                        Button { store.setGridColumnCount(count) } label: {
                            Text("\(count)").font(.callout.weight(.medium)).frame(width: 28,height: 26)
                                .background(store.gridColumns.count == count ? Color.accentColor.opacity(0.18) : Color.clear)
                        }.buttonStyle(.plain).accessibilityLabel(count == 1 ? "Use 1 column" : "Use \(count) columns")
                    }
                }.background(Color.secondary.opacity(0.08),in: RoundedRectangle(cornerRadius: 5))
                Divider().frame(height: 18)
                ForEach(Array(store.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(index == 0 ? "Everything" : node.isLeaf ? store.record(node.activeWindow ?? "")?.app ?? "Window" : "Space") {
                        store.focus(node.id)
                    }.buttonStyle(.plain)
                        .foregroundStyle(node.id == store.focusedNode?.id ? Color.primary : Color.secondary)
                }
                Spacer()
                if store.breadcrumbs.count > 1 {
                    Button("Step Out", systemImage: "arrow.up") { store.zoomOut() }.buttonStyle(.borderless)
                }
            }.font(.caption)
        }.padding(20)
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.2x2").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.accent)
            Text("Start with a window").font(.title2.weight(.semibold))
            Text("Drag a window from Available windows,\nor use its + button to add it to this grid.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Add All Available Windows") { store.addWindowsToCurrentGrid(store.availableRecords.map(\.id)) }.disabled(store.availableRecords.isEmpty)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: String.self) { keys, _ in
                guard let key = keys.first else { return false }
                store.dock(key, target: nil, edge: .right); return true
            }
    }

    @ViewBuilder private func windowActions(_ record: WindowRecord) -> some View {
        Button("Focus in Workspace") {
            store.openWindow(record.id)
        }
        Menu("Dock beside Everything") {
            ForEach([DockEdge.left, .right, .top, .bottom], id: \.rawValue) { edge in
                Button(edge.rawValue.capitalized) { store.dock(record.id, target: store.current?.root?.id, edge: edge) }
            }
        }
        Button("Give Own Column") { _ = store.giveWindowOwnColumn(record.id) }
        Button("Remove from This Grid") { store.removeWindowFromCurrentGrid(record.id) }.disabled(!store.currentGridWindowIDs.contains(record.id))
        if !store.isDemo {
            Divider()
            Button("Always Float \(record.app)") { store.excludeApp(record.bundleID) }
        }
    }
}

struct LayoutCanvas: View {
    var node: LayoutNode
    @ObservedObject var store: WorkspaceStore
    @State private var resizeStart: Double?
    var showsColumnHeader = true

    var body: some View {
        GeometryReader { geometry in
            if showsColumnHeader,let column = node.columnID {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Column \((store.gridColumns.firstIndex { $0.columnID == column } ?? 0)+1)").font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "rectangle.split.1x2").foregroundStyle(.secondary)
                    }.padding(.horizontal,10).frame(height: 28)
                        .background(store.editorDropTarget == "column:\(column)" ? Color.accentColor.opacity(0.22) : Color(nsColor: .windowBackgroundColor),in: RoundedRectangle(cornerRadius: 5))
                        .overlay { if store.editorDropTarget == "column:\(column)" { Text("Stack in this column").font(.caption).padding(4).background(Color(nsColor: .windowBackgroundColor)) } }
                        .background(EditorDropRegion(id: "column:\(column)",node: node.id,columnID: column,store: store).allowsHitTesting(false))
                        .help("Drop here to stack a window in this column")
                    AnyView(LayoutCanvas(node: node,store: store,showsColumnHeader: false))
                }
            } else if node.isSpacer {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.badge.plus").font(.title2)
                    Text("Drop a window").font(.callout.weight(.medium))
                    Text("Use this full column").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
                    .foregroundStyle(store.editorDropTarget == node.id ? Color.accentColor : Color.secondary)
                    .background(Color(nsColor: .controlBackgroundColor),in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3),style: StrokeStyle(lineWidth: 1,dash: [5,4])))
                    .background(EditorDropRegion(id: node.id,node: node.id,store: store).allowsHitTesting(false))
            } else if !node.isLeaf && (geometry.size.width < 140 || geometry.size.height < 100) {
                VStack(spacing: 6) {
                    Image(systemName: "square.split.2x2").font(.title2)
                    if geometry.size.height > 50 { Text("\(node.allWindows.count) windows").font(.caption) }
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity,maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor),in: RoundedRectangle(cornerRadius: 10))
                    .onTapGesture(count: 2) { store.focus(node.id) }
                    .accessibilityLabel("Space with \(node.allWindows.count) windows")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { store.focus(node.id) }
            } else if node.isLeaf { LeafPanel(node: node, store: store) }
            else {
                let horizontal = node.axis == .horizontal
                let extent = horizontal ? geometry.size.width : geometry.size.height
                let seam: CGFloat = 10
                let first = max(0, (extent - seam) * node.ratio)
                let second = max(0, extent - seam - first)
                ZStack(alignment: .topLeading) {
                    AnyView(LayoutCanvas(node: node.children[0], store: store))
                        .frame(width: horizontal ? first : geometry.size.width,
                               height: horizontal ? geometry.size.height : first).clipped()
                    AnyView(LayoutCanvas(node: node.children[1], store: store))
                        .frame(width: horizontal ? second : geometry.size.width,
                               height: horizontal ? geometry.size.height : second).clipped()
                        .offset(x: horizontal ? first + seam : 0, y: horizontal ? 0 : first + seam)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.24))
                        .frame(width: horizontal ? 4 : 36, height: horizontal ? 36 : 4)
                        .frame(width: horizontal ? seam : geometry.size.width,
                               height: horizontal ? geometry.size.height : seam)
                        .contentShape(Rectangle())
                        .offset(x: horizontal ? first : 0, y: horizontal ? 0 : first)
                        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                            if resizeStart == nil { resizeStart = node.ratio; store.beginResize() }
                            let translation = horizontal ? value.translation.width : value.translation.height
                            store.resize(node.id, ratio: (resizeStart ?? node.ratio) + translation / max(1, extent - seam), finished: false)
                        }.onEnded { value in
                            let translation = horizontal ? value.translation.width : value.translation.height
                            store.resize(node.id, ratio: (resizeStart ?? node.ratio) + translation / max(1, extent - seam), finished: true)
                            resizeStart = nil
                        })
                        .accessibilityLabel("Resize \(horizontal ? "horizontal" : "vertical") split")
                        .accessibilityAdjustableAction { direction in
                            store.beginResize()
                            store.resize(node.id, ratio: node.ratio + (direction == .increment ? 0.05 : -0.05), finished: true)
                        }
                }
                .contextMenu {
                    Button("Zoom into This Space") { store.focus(node.id) }
                    Button("Reset Split to Half") { store.beginResize(); store.resize(node.id, ratio: 0.5, finished: true) }
                }
            }
        }
    }
}

private struct LeafPanel: View {
    var node: LayoutNode
    @ObservedObject var store: WorkspaceStore
    private var dropEdge: DockEdge? { store.editorDropTarget == node.id ? store.editorDropEdge : nil }
    private var record: WindowRecord? { store.record(node.activeWindow ?? "") }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 220 || geometry.size.height < 240
            VStack(spacing: 0) {
                if geometry.size.width >= 160 && geometry.size.height >= 80 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(node.windows, id: \.self) { key in
                                HStack(spacing: 0) {
                                Button { store.selectTab(key) } label: {
                                    HStack(spacing: 7) {
                                        AppIcon(record: store.record(key), image: store.icon(key), size: 16)
                                        Text(store.record(key)?.app ?? "Closed window").font(.caption.weight(.medium))
                                        if store.minimized.contains(key) { Image(systemName: "minus.square") }
                                    }.padding(.horizontal, 12).padding(.vertical, 11)
                                        .background(key == node.activeWindow ? Color(nsColor: .controlBackgroundColor) : .clear)
                                }.buttonStyle(.plain)
                                    .overlay { WindowDragSource(key: key,label: store.record(key)?.app ?? "Window",store: store,onSelect: { store.selectTab(key) },onOpen: { store.toggleFocus(node.id) }) }
                                Button { store.removeWindowFromCurrentGrid(key) } label: {
                                    Image(systemName: "xmark").font(.caption2).frame(width: 24,height: 30)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(store.record(key)?.app ?? "window") from this grid")
                                    .help("Remove from this grid; keep the app open")
                                }

                            }
                        }
                    }.background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                }
                ZStack {
                    Palette.tint(record).opacity(0.07)
                    if compact {
                        VStack(spacing: 4) {
                            AppIcon(record: record, image: store.icon(node.activeWindow ?? ""), size: record?.app == "Desktop" ? 26 : 36)
                            if record?.app == "Desktop", geometry.size.height >= 50 {
                                Text("Desktop").font(.caption)
                            }
                        }.accessibilityLabel(record?.app ?? "Window")
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top) {
                                AppIcon(record: record, image: store.icon(node.activeWindow ?? ""), size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record?.app ?? "Window").font(.headline)
                                    Text(record?.title.isEmpty == false ? record!.title : "Untitled window")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Button { store.focus(node.id) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                                    .buttonStyle(.plain).help("Zoom into this window")
                            }
                            if store.isDemo {
                                DemoContent(app: record?.app ?? "").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            } else if let image = store.previews[node.activeWindow ?? ""] {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity,maxHeight: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Spacer(minLength: 0)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.minimized.contains(node.activeWindow ?? "") ? "Minimized" : "Window layout")
                                        .font(.callout.weight(.medium))
                                    Text("Double-click to zoom. Drag a window here to split or tab.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }.padding(20)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .overlay {
                        WindowDragSource(key: node.activeWindow ?? "",label: record?.app ?? "Window",store: store,excludesZoomButton: !compact,
                            onSelect: { store.selectedWindow = node.activeWindow },onOpen: { store.toggleFocus(node.id) })
                    }
            }
            .frame(width: geometry.size.width,height: geometry.size.height)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(dropEdge != nil ? Palette.accent : store.selectedWindow.map(node.windows.contains) == true ? Palette.accent : Color.secondary.opacity(0.18),
                                  lineWidth: dropEdge != nil || store.selectedWindow.map(node.windows.contains) == true ? 2 : 1)
            }
            .overlay(alignment: .topLeading) {
                if let edge = dropEdge {
                    let horizontal = edge == .left || edge == .right
                    let vertical = edge == .top || edge == .bottom
                    RoundedRectangle(cornerRadius: 8).fill(Palette.accent.opacity(0.20))
                        .overlay(Text(edge == .tab ? "App tabs" : edge == .top ? "Stack above" : edge == .bottom ? "Stack below" : store.gridColumns.isEmpty ? "Split \(edge.rawValue)" : "New column").font(.caption.weight(.semibold)))
                        .frame(width: horizontal ? geometry.size.width/2 : geometry.size.width,
                               height: vertical ? geometry.size.height/2 : geometry.size.height)
                        .offset(x: edge == .right ? geometry.size.width/2 : 0,
                                y: edge == .bottom ? geometry.size.height/2 : 0)
                        .allowsHitTesting(false)
                }
            }
            .background(EditorDropRegion(id: node.id,node: node.id,store: store).allowsHitTesting(false))
            .contextMenu {
                Button("Zoom into This Window") { store.focus(node.id) }
                if let key = node.activeWindow { Button("Give Own Column") { _ = store.giveWindowOwnColumn(key) } }
                if let selected = store.selectedWindow, !node.windows.contains(selected) {
                    Menu("Dock Selected Window Here") {
                        ForEach(DockEdge.allCases, id: \.rawValue) { edge in
                            Button(edge == .tab ? "Add as Tab" : edge.rawValue.capitalized) { store.dock(selected, target: node.id, edge: edge) }
                        }
                    }
                }
                Divider()
                ForEach(node.windows, id: \.self) { key in
                    Button("Remove \(store.record(key)?.app ?? "Window") from This Grid") { store.removeWindowFromCurrentGrid(key) }
                }
            }
        }
    }
}

private struct AppIcon: View {
    var record: WindowRecord?
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high) }
            else {
                let name = record?.app.lowercased() ?? ""
                Image(systemName: name == "desktop" ? "desktopcomputer" : name.contains("editor") ? "curlybraces" : name.contains("browser") ? "globe" : name.contains("terminal") ? "terminal" : "note.text")
                    .resizable().scaledToFit().foregroundStyle(Palette.tint(record)).padding(size * 0.12)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct DemoContent: View {
    var app: String
    var body: some View {
        if app == "Editor" {
            VStack(alignment: .leading, spacing: 8) {
                Text("// A workspace is a tree.").foregroundStyle(.secondary)
                Text("struct Space {")
                Text("    var children: [Space]")
                Text("    var windows: [Window]")
                Text("}")
                Spacer(minLength: 12)
                Text("Split a space. Keep your place.").font(.callout).foregroundStyle(.secondary)
            }.font(.system(.callout, design: .monospaced)).foregroundStyle(Palette.tint(nil))
                .lineLimit(1).minimumScaleFactor(0.75)
        } else if app == "Browser" {
            VStack(alignment: .leading, spacing: 12) {
                Text("A desktop with depth.").font(.title3.weight(.semibold))
                Text("Windows become places. Group what belongs together, then zoom into the work in front of you.")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(5)
                Spacer(minLength: 0)
                Label("Sample content", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
            }
        } else if app == "Terminal" {
            VStack(alignment: .leading, spacing: 8) {
                Text("$ swift test")
                Text("Run your layout tests here.").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.font(.system(.caption, design: .monospaced))
        } else if app == "Desktop" {
            VStack(alignment: .leading, spacing: 8) {
                Text("Floating windows live here.").font(.callout.weight(.medium))
                Text("Zoom into Desktop to return to floating windows and wallpaper.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Next up").font(.headline)
                Text("Group related windows\nSave a place to return to\nKeep the desktop in view").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

struct ShortcutHelp: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep your hands on the keys.").font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                ForEach(store.preferences.shortcuts.filter { !$0.id.contains(".") }) { binding in
                    row(binding.title,binding.label)
                }
            }.font(.callout)
            Divider()
            Text("Control–Option–Command + 1–9 switches workspaces. Change workspace, pane, and saved-view combinations in Settings. On the desktop, Option-pinch opens the camera; Shift-drag in the overview frames an area.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 340, alignment: .leading)
        }
    }
    private func row(_ action: String, _ keys: String) -> some View {
        GridRow { Text(action); Text(keys).foregroundStyle(.secondary) }
    }
}
