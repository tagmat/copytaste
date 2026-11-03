import SwiftUI
import AppKit
import QuartzCore
import CopyTasteCore

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: PickerPanel
    private var previousApp: NSRunningApplication?
    var onBecameKey: (() -> Void)?
    var isKey: Bool { panel.isKeyWindow }

    init(model: AppModel) {
        self.model = model
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 460),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.title = "CopyTaste Picker"
        panel.setAccessibilityLabel("CopyTaste clipboard picker")
    }

    func toggle() {
        if panel.isVisible { dismiss(); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.contentView = NSHostingView(rootView: QuickPicker(model: model) { [weak self] entry in
            self?.model.copy(entry)
            self?.dismiss()
        } onDismiss: { [weak self] in self?.dismiss() })
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let destination = NSRect(x: frame.midX - 325, y: frame.midY - 170, width: 650, height: 460)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(destination.offsetBy(dx: 0, dy: reduceMotion ? 0 : -12), display: false)
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(destination, display: true)
        }
    }

    func dismiss() {
        panel.orderOut(nil)
        if previousApp?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) { panel.orderOut(nil) }
    func windowDidBecomeKey(_ notification: Notification) { onBecameKey?() }
}

struct QuickPicker: View {
    @ObservedObject var model: AppModel
    let onChoose: (ClipEntry) -> Void
    let onDismiss: () -> Void
    @State private var query = ""
    @State private var pinnedOnly = false
    @State private var selection = 0
    @State private var hoveredID: UUID?
    @FocusState private var searchFocused: Bool
    private var entries: [ClipEntry] {
        Array(History.search(model.snapshot.entries.filter { !pinnedOnly || $0.isPinned }, query: query).prefix(50))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 30)
                TextField("Find a clip…", text: $query, prompt: Text("Find a clip…").foregroundColor(Palette.railSecondary)).textFieldStyle(.plain)
                    .font(.system(size: 18)).foregroundStyle(.white).tint(.white)
                    .focused($searchFocused).accessibilityLabel("Find a clipboard item")
                    .onSubmit { chooseSelection() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                Button { pinnedOnly.toggle() } label: { Image(systemName: pinnedOnly ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).foregroundStyle(pinnedOnly ? Color.yellow : .white)
                    .accessibilityLabel(pinnedOnly ? "Show all clips" : "Show pinned clips")
                Button(action: onDismiss) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Palette.railSecondary).accessibilityLabel("Close picker")
            }.padding(20).background(Palette.rail).environment(\.colorScheme, .dark)
            if model.isLocked {
                ContentUnavailableView("History is locked", systemImage: "lock.shield", description: Text("Open CopyTaste to unlock it."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Your next good bit goes here." : "No matching clips", systemImage: "square.on.square",
                    description: Text(query.isEmpty ? "Enable capture in CopyTaste, then copy something useful." : "Try a different word or show all clips."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 12) {
                                    Button { onChoose(entry) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: entry.kind.symbol).font(.system(size: 16)).foregroundStyle(Palette.secondary).frame(width: 26)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(entry.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                                Text(entry.sourceName + " · " + entry.kind.label).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                            }
                                            Spacer()
                                            if index == selection { Image(systemName: "return").foregroundStyle(Palette.accent) }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Button { model.togglePin(entry) } label: { Image(systemName: entry.isPinned ? "pin.fill" : "pin") }
                                        .buttonStyle(.plain).foregroundStyle(entry.isPinned ? Palette.accent : Palette.secondary)
                                        .accessibilityLabel(entry.isPinned ? "Unpin \(entry.displayTitle)" : "Pin \(entry.displayTitle)")
                                }.padding(.horizontal, 14).padding(.vertical, 13)
                                    .background(index == selection ? Palette.selection : (hoveredID == entry.id ? Palette.canvas : Color.clear), in: RoundedRectangle(cornerRadius: 9))
                                    .id(entry.id).onHover { hovering in hoveredID = hovering ? entry.id : nil }
                            }
                        }.padding(10)
                    }.onChange(of: selection) { _, value in
                        if entries.indices.contains(value) { proxy.scrollTo(entries[value].id); model.selectedID = entries[value].id }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("CopyTaste").fontWeight(.semibold)
                Text("by tagmat").foregroundStyle(Palette.secondary)
                Spacer()
                Text("↑ ↓ select    ↵ copy    esc close").foregroundStyle(Palette.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 20).frame(height: 36)
                .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 1) }
        }.background(Palette.paper).foregroundStyle(Palette.ink).clipShape(RoundedRectangle(cornerRadius: 18))
            .preferredColorScheme(.light)
            .defaultFocus($searchFocused, true)
            .onAppear { model.selectedID = entries.first?.id }
            .task { await Task.yield(); searchFocused = true }
            .onChange(of: query) { _, _ in resetSelection() }
            .onChange(of: pinnedOnly) { _, _ in resetSelection() }
            .onChange(of: model.isLocked) { _, locked in if locked { query = ""; onDismiss() } }
            .onExitCommand(perform: onDismiss)
    }

    private func resetSelection() { selection = 0; model.selectedID = entries.first?.id }
    private func move(_ direction: Int) {
        guard !entries.isEmpty else { return }
        selection = (selection + direction + entries.count) % entries.count
        model.selectedID = entries[selection].id
    }
    private func chooseSelection() {
        guard entries.indices.contains(selection), !model.isLocked else { return }
        onChoose(entries[selection])
    }
}
