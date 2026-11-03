import SwiftUI
import AppKit
import Carbon

@main
struct CopyTasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        Window("CopyTaste", id: "history") {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear { delegate.model = model }
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands { HistoryCommands(model: delegate.commandModel ?? model, delegate: delegate) }
    }
}

struct HistoryCommands: Commands {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    var body: some Commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { (delegate.activeCommandModel ?? model).showSettings = true }
                    .keyboardShortcut(",")
            }
            CommandMenu("History") {
                Button("Show Picker") { delegate.showPicker() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button(model.isCapturing ? "Pause Capture" : "Resume Capture") { (delegate.activeCommandModel ?? model).toggleCapture() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(model.isLocked || model.isDemo)
                Button("Lock History") { (delegate.activeCommandModel ?? model).lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Copy Selected") {
                    let active = delegate.activeCommandModel ?? model
                    if let item = active.selectedEntry { active.copy(item) }
                }
                    .keyboardShortcut(.return, modifiers: .command).disabled(model.selectedEntry == nil)
            }
            CommandGroup(after: .help) {
                Button("Explore Sample History") { delegate.showDemo() }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    weak var model: AppModel?
    @Published var commandModel: AppModel?
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var demoController: NSWindowController?
    private var demoModel: AppModel?
    private var pickerController: PickerController?
    private var demoPickerController: PickerController?
    private var focusObservers: [NSObjectProtocol] = []
    var activeCommandModel: AppModel? {
        if demoPickerController?.isKey == true || (NSApp.isActive && demoController?.window?.isKeyWindow == true) { return demoModel }
        return model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.commandModel = self?.activeCommandModel }
            })
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "CopyTaste")
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        statusItem = item
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().showPicker()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: 0x43545950, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            Task { @MainActor [weak self] in
                self?.model?.errorMessage = "The ⇧⌘V shortcut is in use. Open CopyTaste from the menu bar instead."
            }
        }
    }

    @objc private func statusClicked() { showHistory() }
    func showHistory() {
        commandModel = model
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "CopyTaste" }?.makeKeyAndOrderFront(nil)
    }
    func showPicker() {
        guard let active = activeCommandModel ?? model else { return }
        if active.isDemo {
            if demoPickerController == nil { demoPickerController = PickerController(model: active) }
            demoPickerController?.onBecameKey = { [weak self, weak active] in self?.commandModel = active }
            demoPickerController?.toggle()
            return
        }
        let model = active
        if model.isLocked { showHistory(); return }
        if pickerController == nil { pickerController = PickerController(model: model) }
        pickerController?.onBecameKey = { [weak self, weak model] in self?.commandModel = model }
        commandModel = model
        pickerController?.toggle()
    }
    func showDemo() {
        if let demoController { demoController.showWindow(nil); demoController.window?.makeKeyAndOrderFront(nil); return }
        let demo = AppModel(demo: true)
        demoModel = demo
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "CopyTaste Demo"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 980, height: 620)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: demo).preferredColorScheme(.light))
        window.center()
        let controller = NSWindowController(window: window)
        demoController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowDidBecomeKey(_ notification: Notification) { commandModel = demoModel }
    func windowDidResignKey(_ notification: Notification) { commandModel = model }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        demoModel?.shutdown()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
