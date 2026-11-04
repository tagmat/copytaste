import SwiftUI
import AppKit
import Carbon
import CopyTasteCore

@main
struct CopyTasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings {
            SettingsView(model: delegate.model, onShowPicker: { delegate.showPicker() },
                onShortcutChange: { delegate.changeSelectorShortcut($0) })
        }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Advanced Settings…") { delegate.showAdvancedSettings() }.keyboardShortcut(",")
                }
            }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(demo: CommandLine.arguments.contains("--demo") || Bundle.main.object(forInfoDictionaryKey: "CopyTastePreviewMode") as? Bool == true)
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var picker: PickerController?
    private var samplePicker: PickerController?
    private var sampleModel: AppModel?
    private var settingsController: NSWindowController?
    private var activationObserver: NSObjectProtocol?
    private var lastDestination: PasteDestination?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        rememberDestination()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rememberDestination() }
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "CopyTaste")
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        statusItem = item
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().showPicker() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        _ = registerSelectorShortcut(model.preferences.selectorShortcut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.model.isDemo { self.showPicker() }
            else if !self.model.preferences.captureEnabled { self.showPopover() }
        }
    }

    func changeSelectorShortcut(_ shortcut: SelectorShortcut) {
        guard shortcut != model.preferences.selectorShortcut, registerSelectorShortcut(shortcut) else { return }
        model.setSelectorShortcut(shortcut)
    }

    private func registerSelectorShortcut(_ shortcut: SelectorShortcut) -> Bool {
        if model.isDemo { return true }
        let modifiers: Int
        switch shortcut {
        case .shiftCommand: modifiers = cmdKey | shiftKey
        case .optionCommand: modifiers = cmdKey | optionKey
        case .controlOption: modifiers = controlKey | optionKey
        case .disabled:
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            return true
        }
        var registration: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(modifiers), EventHotKeyID(signature: 0x43545950, id: 1),
            GetApplicationEventTarget(), 0, &registration)
        guard result == noErr, let registration else {
            model.errorMessage = "The \(shortcut.label) shortcut could not be registered. Choose another in advanced settings or use the menu bar."
            return false
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = registration
        return true
    }

    private func rememberDestination() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "net.tagmat.copytaste", app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastDestination = PasteDestination(processID: app.processIdentifier, name: app.localizedName ?? "your app")
    }

    @objc private func statusClicked() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        rememberDestination()
        picker?.dismiss(immediately: true)
        samplePicker?.dismiss(immediately: true)
        guard let button = statusItem?.button else { return }
        popover.contentViewController = NSHostingController(rootView: QuickSettingsView(model: model,
            onPicker: { [weak self] in self?.showPicker() }, onAdvanced: { [weak self] in self?.showAdvancedSettings() },
            onSamples: { [weak self] in self?.showSamples() }))
        if let view = popover.contentViewController?.view { popover.contentSize = NSSize(width: 340, height: view.fittingSize.height) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func showPicker() {
        rememberDestination()
        popover.performClose(nil)
        if picker == nil {
            picker = PickerController(model: model)
            picker?.onSettings = { [weak self] in self?.showPopover() }
            picker?.onPermissionRequired = { [weak self] in self?.showPopover() }
        }
        picker?.toggle(destination: lastDestination)
    }

    func showSamples() {
        popover.performClose(nil)
        picker?.dismiss(immediately: true)
        if sampleModel == nil { sampleModel = AppModel(demo: true) }
        guard let sampleModel else { return }
        if samplePicker == nil {
            samplePicker = PickerController(model: sampleModel)
            samplePicker?.onSettings = { [weak self] in self?.showPopover() }
        }
        samplePicker?.toggle(destination: nil)
    }

    func showAdvancedSettings() {
        popover.performClose(nil)
        picker?.dismiss(immediately: true)
        samplePicker?.dismiss(immediately: true)
        if settingsController == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "CopyTaste · Advanced Settings"
            window.minSize = NSSize(width: 600, height: 600)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: SettingsView(model: model,
                onShowPicker: { [weak self] in self?.showPicker() },
                onShortcutChange: { [weak self] in self?.changeSelectorShortcut($0) }))
            window.center()
            settingsController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if picker?.isVisible == true { picker?.focus(); return false }
        if samplePicker?.isVisible == true { samplePicker?.focus(); return false }
        showPopover()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown(); sampleModel?.shutdown()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
