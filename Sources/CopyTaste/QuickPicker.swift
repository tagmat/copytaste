import SwiftUI
import AppKit
import CopyTasteCore

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PickerPresentation: ObservableObject {
    enum Phase { case closed, open, departing }
    @Published var phase: Phase = .closed
    @Published var chosenID: UUID?
    @Published var navigationStep = 0
    var allowsScrollNavigation = true
}

@MainActor final class PickerController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: PickerPanel
    private let presentation = PickerPresentation()
    private let pasteService = PasteService()
    private var destination: PasteDestination?
    private var generation = 0
    private var scrollMonitor: Any?
    private var scrollDistance: CGFloat = 0
    private var lastScroll = Date.distantPast
    var onSettings: (() -> Void)?
    var onPermissionRequired: (() -> Void)?
    var isKey: Bool { panel.isKeyWindow }
    var isVisible: Bool { panel.isVisible }

    func focus() {
        guard panel.isVisible else { return }
        generation += 1
        presentation.chosenID = nil
        presentation.phase = .open
        panel.makeKeyAndOrderFront(nil)
    }

    init(model: AppModel) {
        self.model = model
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 560),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.title = "CopyTaste Picker"
        panel.setAccessibilityLabel("CopyTaste floating clipboard selector")
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible,
                  self.presentation.phase == .open, self.presentation.allowsScrollNavigation else { return event }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            if event.phase == .began { self.scrollDistance = 0 }
            if event.momentumPhase != [] { return nil }
            self.scrollDistance += delta
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 28 : 1
            if abs(self.scrollDistance) >= threshold, Date().timeIntervalSince(self.lastScroll) >= 0.09 {
                self.presentation.navigationStep += self.scrollDistance < 0 ? 1 : -1
                self.scrollDistance = 0; self.lastScroll = Date()
            }
            return nil
        }
    }

    func toggle(destination: PasteDestination?) {
        if panel.isVisible { dismiss(); return }
        generation += 1
        self.destination = model.isDemo ? nil : destination
        scrollDistance = 0
        lastScroll = .distantPast
        presentation.phase = .closed
        presentation.chosenID = nil
        presentation.allowsScrollNavigation = true
        panel.contentView = NSHostingView(rootView: QuickPicker(model: model, presentation: presentation,
            onChoose: { [weak self] entry, copyOnly in self?.choose(entry, copyOnly: copyOnly) },
            onDismiss: { [weak self] in self?.dismiss() }, onSettings: { [weak self] in self?.onSettings?() }))
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1120, available.width - 40)
        panel.setFrame(NSRect(x: available.midX - width / 2, y: available.midY - 240, width: width, height: 560), display: true)
        panel.makeKeyAndOrderFront(nil)
        let ticket = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.generation == ticket else { return }
            self.presentation.phase = .open
        }
    }

    func dismiss(immediately: Bool = false) {
        generation += 1
        let ticket = generation
        presentation.chosenID = nil
        presentation.phase = .departing
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !immediately && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard self.generation == ticket else { return }
            self.panel.orderOut(nil)
            self.presentation.phase = .closed
            self.panel.contentView = nil
        }
    }

    private func choose(_ entry: ClipEntry, copyOnly: Bool) {
        guard !model.isLocked, presentation.phase == .open else { return }
        generation += 1
        let ticket = generation
        let target = destination
        presentation.chosenID = entry.id
        presentation.phase = .departing
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { try? await Task.sleep(for: .milliseconds(180)) }
            guard self.generation == ticket, !self.model.isLocked else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
            let outcome = await self.pasteService.perform(copy: { self.model.copy(entry) }, destination: target,
                automatic: self.model.preferences.autoPaste && !copyOnly, demo: self.model.isDemo,
                stillValid: { self.generation == ticket && !self.model.isLocked },
                clipboardIsCurrent: { self.model.ownsCurrentClipboard })
            guard self.generation == ticket, !self.model.isLocked else { return }
            switch outcome {
            case .pasted: self.model.notify("Paste sent to \(target?.name ?? "your app")")
            case .permissionRequired:
                self.model.notify("Copied. Allow Accessibility for direct paste.")
                self.onPermissionRequired?()
            case .destinationChanged: self.model.notify("Copied. Destination changed; paste with ⌘V.")
            case .clipboardChanged: self.model.notify("Clipboard changed. No paste was sent.")
            case .copied:
                if !self.model.isDemo, let target { _ = NSRunningApplication(processIdentifier: target.processID)?.activate() }
            case .failed: break
            }
            guard self.generation == ticket else { return }
            self.presentation.phase = .closed
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if presentation.phase == .open { dismiss(immediately: true) }
    }
}

enum PickerFilter: String, CaseIterable {
    case all = "All", pinned = "Pinned", text = "Text", links = "Links", images = "Images", files = "Files"
    var symbol: String {
        switch self { case .all: "square.stack.3d.up"; case .pinned: "pin"; case .text: "text.alignleft"; case .links: "link"; case .images: "photo"; case .files: "doc" }
    }
    func includes(_ entry: ClipEntry) -> Bool {
        switch self { case .all: true; case .pinned: entry.isPinned; case .text: entry.kind == .text; case .links: entry.kind == .link; case .images: entry.kind == .image; case .files: entry.kind == .file }
    }
}

struct PickerSlot: Equatable {
    let index: Int
    let offset: Int
}

enum PickerLayout {
    static func ordered(_ entries: [ClipEntry], layout: SelectorLayout) -> [ClipEntry] {
        entries.sorted {
            if layout == .pinnedAndRecent && $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    static func slots(count: Int, selection: Int) -> [PickerSlot] {
        guard count > 0 else { return [] }
        let visible = min(7, count)
        let first = -((visible - 1) / 2)
        let selected = min(max(0, selection), count - 1)
        return (first..<(first + visible)).map { PickerSlot(index: (selected + $0 + count) % count, offset: $0) }
    }
}

struct QuickPicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PickerPresentation
    let onChoose: (ClipEntry, Bool) -> Void
    let onDismiss: () -> Void
    let onSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var filter = PickerFilter.all
    @State private var selection = 0
    @State private var collectionID: UUID?
    @State private var syncPassphrase = ""
    @State private var draft: ClipDraft?
    @State private var batchIDs: [UUID] = []
    @State private var showsBatch = false
    @State private var batchSeparator = BatchSeparator.lines
    @State private var indexedImageIDs: Set<UUID> = []
    @State private var imageText: [UUID: String] = [:]
    @FocusState private var searchFocused: Bool
    private static let numberKeys = Set("123456789".map { KeyEquivalent($0) })

    private var entries: [ClipEntry] {
        let matches = History.search(model.snapshot.entries.filter {
            filter.includes($0) && (collectionID == nil || $0.collectionID == collectionID)
        }, query: query, imageText: model.preferences.imageTextSearch ? imageText : [:])
        return PickerLayout.ordered(matches, layout: model.preferences.selectorLayout)
    }
    private var pinned: [ClipEntry] { entries.filter(\.isPinned) }
    private var recent: [ClipEntry] { entries.filter { !$0.isPinned } }
    private var splitLayout: Bool { model.preferences.selectorLayout == .pinnedAndRecent && filter != .pinned && !pinned.isEmpty && !recent.isEmpty }
    private var selected: ClipEntry? { entries.indices.contains(selection) ? entries[selection] : nil }
    private var isOpen: Bool { presentation.phase == .open }
    private var workflowOpen: Bool { draft != nil || showsBatch }
    private var batchEntries: [ClipEntry] {
        batchIDs.compactMap { id in model.snapshot.entries.first { $0.id == id } }
    }
    private var numberedClips: [ClipEntry] {
        Array(PickerLayout.ordered(entries, layout: .orbit).prefix(9))
    }
    private var imagesToIndex: [ClipEntry] {
        guard isOpen, !model.isLocked, model.preferences.imageTextSearch else { return [] }
        return Array(model.snapshot.entries.filter { $0.kind == .image && $0.imageData != nil }.prefix(60))
    }

    var body: some View {
        Group {
            if !model.isLocked, let binding = Binding($draft) {
                ClipEditor(draft: binding, onSave: saveDraft, onClose: closeWorkflow)
            } else if !model.isLocked && showsBatch {
                let batch = batchEntries
                let output = ClipBatch.text(batch, separator: batchSeparator)
                BatchPreview(entries: batch, separator: $batchSeparator, canPaste: output != nil,
                    automaticPaste: model.preferences.autoPaste,
                    onRemove: { id in batchIDs.removeAll { $0 == id } }, onClear: { batchIDs.removeAll() },
                    onClose: closeWorkflow, onDeliver: { copyOnly in
                        if let output {
                            let clip = ClipEntry(kind: .text, text: output, sourceName: "Batch", sourceBundleID: CapturePolicy.ownBundleID)
                            onChoose(clip, copyOnly)
                        }
                    })
            } else {
                pickerBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Palette.text).tint(Palette.mint).preferredColorScheme(.dark)
        .task { await Task.yield(); searchFocused = true; resetSelection() }
        .task(id: imagesToIndex.map(\.id)) { await indexImages(imagesToIndex) }
        .onChange(of: workflowOpen) { _, open in presentation.allowsScrollNavigation = !open }
        .onChange(of: query) { _, _ in resetSelection() }
        .onChange(of: filter) { _, _ in resetSelection() }
        .onChange(of: collectionID) { _, _ in resetSelection() }
        .onChange(of: model.preferences.selectorLayout) { _, _ in resetSelection() }
        .onChange(of: presentation.navigationStep) { old, new in if !workflowOpen { move(new - old) } }
        .onChange(of: entries.map(\.id)) { _, identifiers in
            if let id = model.selectedID, let index = identifiers.firstIndex(of: id) { selection = index }
            else { selection = min(selection, max(0, entries.count - 1)) }
            model.selectedID = selected?.id
        }
        .onChange(of: model.isLocked) { _, locked in
            if locked {
                query = ""
                batchIDs.removeAll()
                draft = nil
                showsBatch = false
                imageText.removeAll()
                indexedImageIDs.removeAll()
                onDismiss()
            }
        }
        .onExitCommand { if workflowOpen { closeWorkflow() } else { onDismiss() } }
        .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.82), value: selection)
    }

    private var pickerBody: some View {
        VStack(spacing: 0) {
            searchBar.padding(.top, 22)
            GeometryReader { geometry in
                if model.isLocked { lockedState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if entries.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    if splitLayout {
                        HStack(spacing: 14) {
                            pinnedStack.frame(width: 222)
                            VStack(spacing: 0) {
                                Text("Recent · newest first")
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .modifier(FrostedSurface(radius: 10)).padding(.top, 6)
                                fan(recent, width: geometry.size.width - 260, insideSplit: true)
                            }
                        }.padding(.horizontal, 12)
                    } else { fan(entries, width: geometry.size.width) }
                }
            }
            controlStrip.padding(.bottom, 18)
        }.defaultFocus($searchFocused, true)
    }

    private func fan(_ values: [ClipEntry], width: CGFloat, insideSplit: Bool = false) -> some View {
        let index = values.firstIndex { $0.id == selected?.id } ?? 0
        // Leave room for the outer cards and their shadows within the recent column.
        let spread = insideSplit ? max(0, (width - 350) / 6) : min(196, (width - 310) / 3.7)
        let numbers = numberedClips.map(\.id)
        return ZStack {
            ForEach(PickerLayout.slots(count: values.count, selection: index), id: \.index) { slot in
                let entry = values[slot.index]
                card(entry, number: numbers.firstIndex(of: entry.id).map { $0 + 1 }, delta: Double(slot.offset), spread: spread)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinnedStack: some View {
        let active = pinned.first { $0.id == selected?.id } ?? pinned.first
        let values = [active].compactMap { $0 } + pinned.filter { $0.id != active?.id }.prefix(2)
        let numbers = numberedClips.map(\.id)
        return VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill"); Text("Pinned"); Text("\(pinned.count)").foregroundStyle(Palette.secondary)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint)
                .padding(.horizontal, 10).padding(.vertical, 5).modifier(FrostedSurface(radius: 10))
            ZStack {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, entry in
                    FlightCard(entry: entry, selected: entry.id == selected?.id, number: numbers.firstIndex(of: entry.id).map { $0 + 1 },
                        onChoose: { onChoose(entry, false) }, onPin: { model.togglePin(entry) })
                        .contextMenu { clipActions(entry) }
                        .frame(width: 278, height: 300).scaleEffect(0.72)
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(index) * -5))
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * 9)
                        .zIndex(Double(3 - index))
                }
            }.frame(width: 210, height: 244)
            Button { filter = .pinned } label: {
                Text("Show all pins").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5).modifier(FrostedSurface(radius: 10))
            }.buttonStyle(.plain)
        }.opacity(isOpen ? 1 : 0).offset(x: isOpen || reduceMotion ? 0 : -100)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: isOpen)
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            BrandMark(size: 34)
            TextField("Search your orbit", text: $query, prompt: Text("Search your orbit").foregroundColor(Palette.secondary))
                .textFieldStyle(.plain).font(.system(size: 17)).focused($searchFocused)
                .accessibilityLabel("Search clipboard history").onSubmit { choose(copyOnly: false) }
                .onKeyPress(keys: [.return], phases: .down) { event in
                    if event.modifiers.contains(.option) { choose(copyOnly: true); return .handled }
                    return .ignored
                }
                .onKeyPress(.leftArrow) { move(-1); return .handled }
                .onKeyPress(.rightArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(keys: Self.numberKeys, phases: .down) { press in
                    guard press.modifiers == .command, let number = press.key.character.wholeNumberValue else { return .ignored }
                    let clips = numberedClips
                    if clips.indices.contains(number - 1), !model.isLocked { onChoose(clips[number - 1], false) }
                    return .handled
                }
                .onKeyPress(keys: ["b", "e", "n"], phases: .down) { press in
                    guard press.modifiers == .command, !model.isLocked else { return .ignored }
                    switch press.key.character {
                    case "b": if let selected { addToBatch(selected) }
                    case "e": if let selected { draft = ClipDraft(selected) }
                    case "n": draft = ClipDraft()
                    default: break
                    }
                    return .handled
                }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
            Text("\(entries.count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Palette.secondary)
            if !query.isEmpty && imagesToIndex.contains(where: { !indexedImageIDs.contains($0.id) }) {
                ProgressView().controlSize(.mini).accessibilityLabel("Reading text from images")
            }
            IconButton(symbol: "slider.horizontal.3", label: "Quick settings", action: onSettings)
            IconButton(symbol: "xmark", label: "Close selector", action: onDismiss)
        }.padding(14).frame(maxWidth: 700).modifier(FrostedSurface(radius: 25))
            .opacity(isOpen ? 1 : 0).offset(y: isOpen || reduceMotion ? 0 : -24)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }

    private func card(_ entry: ClipEntry, number: Int?, delta: Double, spread: CGFloat) -> some View {
        let chosen = presentation.chosenID == entry.id
        let departing = presentation.phase == .departing
        let x = isOpen || reduceMotion ? delta * spread : (departing ? delta * (spread + 45) : delta * 18)
        let y = isOpen || reduceMotion ? abs(delta) * 11 : (departing ? (chosen ? -160.0 : 95.0) : 130.0)
        return FlightCard(entry: entry, selected: entry.id == selected?.id, number: number,
            onChoose: { onChoose(entry, false) }, onPin: { model.togglePin(entry) })
            .frame(width: 278, height: 300)
            .contextMenu { clipActions(entry) }
            .scaleEffect(reduceMotion ? 1 : (isOpen ? max(0.82, 1 - abs(delta) * 0.055) : (chosen ? 1.06 : 0.68)))
            .rotationEffect(.degrees(reduceMotion ? 0 : (isOpen ? delta * 3.2 : delta * 10)))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : (isOpen ? -delta * 8 : 35)), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .offset(x: x, y: y).opacity(isOpen ? 1 : 0)
            .blur(radius: reduceMotion || isOpen ? 0 : 9).zIndex(10 - abs(delta))
            .animation(reduceMotion ? nil : (departing ? .easeIn(duration: 0.18) : .spring(response: 0.58, dampingFraction: 0.76).delay(abs(delta) * 0.025)), value: presentation.phase)
    }

    @ViewBuilder private func clipActions(_ entry: ClipEntry) -> some View {
        Button("Paste") { onChoose(entry, false) }
        Button("Copy Only") { onChoose(entry, true) }
        Button(entry.text == nil ? "Rename…" : "Edit Clip…") { draft = ClipDraft(entry) }
        if entry.text != nil {
            Button(batchIDs.contains(entry.id) ? "Remove from Batch" : "Add to Batch") { addToBatch(entry) }
        }
        Button(entry.isPinned ? "Unpin" : "Pin") { model.togglePin(entry) }
        Menu("Collection") {
            Button("None") { model.move(entry, to: nil) }
            ForEach(model.snapshot.collections) { collection in Button(collection.name) { model.move(entry, to: collection.id) } }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(entry) }
    }

    private var controlStrip: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(PickerFilter.allCases, id: \.self) { item in
                    Button { filter = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .foregroundStyle(filter == item ? Palette.background : Palette.secondary)
                            .background(filter == item ? Palette.mint : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
                if !model.snapshot.collections.isEmpty {
                    Menu {
                        Button("All collections") { collectionID = nil }
                        ForEach(model.snapshot.collections) { collection in Button(collection.name) { collectionID = collection.id } }
                    } label: { Image(systemName: "folder").padding(8) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Filter collection")
                }
            }.padding(6).modifier(FrostedSurface(radius: 24))
            HStack(spacing: 18) {
                Label(model.isDemo ? "Sample orbit" : model.storageLabel, systemImage: "memorychip")
                Text("scroll / ← →")
                Text(model.preferences.autoPaste ? "↵ paste" : "↵ copy")
                Text("⌥↵ copy only")
                Button { if let selected { model.togglePin(selected) } } label: { Label("Pin", systemImage: "pin") }
                    .buttonStyle(.plain).keyboardShortcut("p", modifiers: .command).disabled(selected == nil)
                Button { draft = ClipDraft() } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.plain).accessibilityLabel("New snippet").disabled(model.isLocked)
                Button { showsBatch = true } label: {
                    Label(batchEntries.isEmpty ? "Batch" : "Batch \(batchEntries.count)", systemImage: "list.number")
                }.buttonStyle(.plain).disabled(model.isLocked)
                Text("by tagmat").foregroundStyle(Palette.mint)
            }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 14).padding(.vertical, 9).modifier(FrostedSurface(radius: 17))
        }.opacity(isOpen ? 1 : 0).animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isOpen)
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.mint)
            Text(query.isEmpty ? "A little space for your next idea." : "Nothing in this orbit.")
                .font(.system(size: 22, weight: .medium, design: .rounded))
            Text(query.isEmpty ? "Copy text, an image, a link or a file. It will float right here." : "Try another word or a different filter.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            if !model.isCapturing && !model.isDemo {
                Button("Start Capture") { model.toggleCapture() }.buttonStyle(.borderedProminent)
            }
        }.padding(32).modifier(FrostedSurface()).padding(32).opacity(isOpen ? 1 : 0)
    }

    private var lockedState: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.shield").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.mint)
            Text("Your orbit is private.").font(.system(size: 24, weight: .medium, design: .rounded))
            Text(model.preferences.storageMode == .memory ? "The memory session was cleared." : "Authenticate to unlock encrypted history.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            if model.preferences.storageMode == .iCloud { SecureField("Sync passphrase", text: $syncPassphrase).textFieldStyle(.roundedBorder).frame(width: 270) }
            Button(model.isAuthenticating ? "Unlocking…" : "Unlock") {
                let phrase = syncPassphrase; syncPassphrase = ""
                Task { await model.unlock(syncPassphrase: phrase) }
            }.buttonStyle(.borderedProminent).disabled(model.isAuthenticating)
        }.padding(30).modifier(FrostedSurface()).opacity(isOpen ? 1 : 0)
    }
    private func resetSelection() {
        selection = model.preferences.selectorLayout == .pinnedAndRecent && filter != .pinned ? (entries.firstIndex { !$0.isPinned } ?? 0) : 0
        model.selectedID = selected?.id
    }
    private func move(_ direction: Int) {
        guard !entries.isEmpty else { return }
        selection = (selection + direction + entries.count) % entries.count
        model.selectedID = selected?.id
    }
    private func choose(copyOnly: Bool) { if let selected, !model.isLocked { onChoose(selected, copyOnly) } }

    private func addToBatch(_ entry: ClipEntry) {
        guard entry.kind == .text || entry.kind == .link else { return }
        if batchIDs.contains(entry.id) { batchIDs.removeAll { $0 == entry.id }; return }
        let valid = Set(model.snapshot.entries.map(\.id))
        batchIDs.removeAll { !valid.contains($0) }
        if batchIDs.count < ClipBatch.limit { batchIDs.append(entry.id) }
        else { showsBatch = true }
    }

    private func saveDraft() -> String? {
        guard let draft else { return nil }
        if let issue = model.saveClip(id: draft.id, title: draft.title, text: draft.text) { return issue }
        closeWorkflow()
        return nil
    }

    private func closeWorkflow() {
        draft = nil
        showsBatch = false
        searchFocused = true
    }

    private func indexImages(_ entries: [ClipEntry]) async {
        let ids = Set(entries.map(\.id))
        indexedImageIDs.formIntersection(ids)
        imageText = imageText.filter { ids.contains($0.key) }
        for entry in entries where !indexedImageIDs.contains(entry.id) {
            guard !Task.isCancelled, let bytes = entry.imageData else { return }
            let recognized = await ImageTextRecognition.shared.recognize(bytes)
            guard !Task.isCancelled, isOpen, !model.isLocked, model.preferences.imageTextSearch,
                  model.snapshot.entries.contains(where: { $0.id == entry.id }) else { return }
            imageText[entry.id] = recognized
            indexedImageIDs.insert(entry.id)
        }
    }
}

private struct FlightCard: View {
    let entry: ClipEntry
    let selected: Bool
    let number: Int?
    let onChoose: () -> Void
    let onPin: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = CGPoint.zero
    var body: some View {
        let previewText = String((entry.text ?? "").prefix(8_000))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(entry.kind.label, systemImage: entry.kind.symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.kind == .image || entry.kind == .file ? Palette.violet : Palette.mint)
                Spacer()
                if let number { Text("⌘\(number)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.secondary) }
                Button(action: onPin) { Image(systemName: entry.isPinned ? "pin.fill" : "pin").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(entry.isPinned ? Palette.mint : Palette.secondary)
                    .accessibilityLabel((entry.isPinned ? "Unpin " : "Pin ") + String(entry.displayTitle.prefix(90)))
            }.padding(18)
            Button(action: onChoose) {
                VStack(alignment: .leading, spacing: 12) {
                    if entry.kind == .file { FilePreview(entry: entry) }
                    else if entry.kind == .image, let image = PreviewCache.shared.thumbnail(entry) {
                        Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 174).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Copied image")
                    } else if entry.kind == .link {
                        Image(systemName: "arrow.up.right").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Palette.violet)
                        Text(entry.displayTitle).font(.system(size: 20, weight: .medium, design: .rounded)).lineLimit(3)
                        Text(URL(string: entry.text ?? "")?.host ?? "Link").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                    } else if let swatch = hexSwatch(previewText) {
                        RoundedRectangle(cornerRadius: 12).fill(swatch).frame(height: 136)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
                            .accessibilityHidden(true)
                        Text(previewText).font(.system(size: 18, weight: .medium, design: .monospaced))
                    } else if PreviewFormatting.isMarkdown(previewText) {
                        MarkdownPreview(source: previewText).frame(maxHeight: 190).clipped()
                    } else if PreviewFormatting.isCode(previewText) {
                        CodePreview(source: previewText, lines: 10)
                    } else {
                        Text(String(previewText.prefix(1_800))).font(.system(size: 18, weight: .medium, design: .rounded)).lineSpacing(5).lineLimit(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 18)
                .accessibilityLabel("Paste \(entry.kind.label.lowercased()) from \(entry.sourceName): \(String(entry.displayTitle.prefix(90)))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            HStack {
                Text(entry.sourceName).lineLimit(1)
                Spacer()
                Text(entry.createdAt, style: .relative).lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(18)
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Palette.mint.opacity(0.8) : .white.opacity(0.12), lineWidth: selected ? 1.2 : 0.6))
            .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 20)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(tilt.x) * 3), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -Double(tilt.y) * 3), axis: (x: 1, y: 0, z: 0))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): tilt = CGPoint(x: (point.x - 139) / 139, y: (point.y - 150) / 150)
                case .ended: tilt = .zero
                }
            }
    }

    private func hexSwatch(_ text: String) -> Color? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.dropFirst()
        guard value.first == "#", digits.count == 3 || digits.count == 6,
              digits.allSatisfy(\.isHexDigit), let code = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 3 {
            return Color(red: Double((code >> 8) & 15) / 15,
                green: Double((code >> 4) & 15) / 15, blue: Double(code & 15) / 15)
        }
        return Color(red: Double((code >> 16) & 255) / 255,
            green: Double((code >> 8) & 255) / 255, blue: Double(code & 255) / 255)
    }
}
