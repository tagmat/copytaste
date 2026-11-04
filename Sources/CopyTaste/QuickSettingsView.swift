import SwiftUI
import AppKit
import CopyTasteCore

struct QuickSettingsView: View {
    @ObservedObject var model: AppModel
    let onPicker: () -> Void
    let onAdvanced: () -> Void
    let onSamples: () -> Void
    @State private var trusted = PasteService.hasAccess
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CopyTaste").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("by tagmat").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                IconButton(symbol: "gearshape", label: "Advanced settings", action: onAdvanced)
            }
            HStack(spacing: 6) {
                Circle().fill(model.isCapturing ? Palette.mint : Palette.secondary).frame(width: 6, height: 6)
                Text(model.isLocked ? "Locked" : (model.isCapturing ? "Capturing" : "Capture paused"))
                Spacer()
                Text("\(model.snapshot.entries.count) clips").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Button(action: onPicker) {
                HStack { Text(model.isLocked ? "Unlock your orbit" : "Open your orbit"); Spacer(); Text("⇧⌘V").opacity(0.65) }
                    .font(.system(size: 13, weight: .semibold)).padding(14).foregroundStyle(Palette.background)
                    .background(Palette.mint, in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain)
            VStack(spacing: 16) {
                toggle("Capture", subtitle: "Private apps are always excluded", symbol: "shield.lefthalf.filled",
                    value: Binding(get: { model.isCapturing }, set: { if $0 != model.isCapturing { model.toggleCapture() } }))
                    .disabled(model.isLocked || model.isDemo)
                toggle("Paste on selection", subtitle: "Back into your previous app", symbol: "arrow.up.forward.app",
                    value: Binding(get: { model.preferences.autoPaste }, set: { model.setAutoPaste($0) }))
                toggle("Images", subtitle: "Keep pixels, not their link", symbol: "photo",
                    value: Binding(get: { model.preferences.captureImages }, set: { model.setCaptureImages($0) }))
                toggle("Files & previews", subtitle: "PDF, documents, archives · up to 8 MB", symbol: "doc",
                    value: Binding(get: { model.preferences.captureFiles }, set: { model.setCaptureFiles($0) }))
            }
            HStack {
                Label("Selector layout", systemImage: "rectangle.3.group").font(.system(size: 11))
                Spacer()
                Picker("Selector layout", selection: Binding(get: { model.preferences.selectorLayout }, set: { model.setSelectorLayout($0) })) {
                    Text("Pinned + recent").tag(SelectorLayout.pinnedAndRecent)
                    Text("Single orbit").tag(SelectorLayout.orbit)
                }.labelsHidden().pickerStyle(.menu).frame(width: 144).font(.system(size: 11))
            }
            if model.preferences.autoPaste && !trusted && !model.isDemo {
                VStack(alignment: .leading, spacing: 9) {
                    Text("One permission. Then just choose.").font(.system(size: 12, weight: .medium))
                    Text("Allow Accessibility so CopyTaste can paste into the app you came from.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Enable Direct Paste") { PasteService.requestAccess(); trusted = PasteService.hasAccess }
                        .buttonStyle(.bordered).controlSize(.small)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Palette.raised, in: RoundedRectangle(cornerRadius: 13))
            }
            Button(action: onAdvanced) {
                HStack {
                    Image(systemName: model.preferences.storageMode == .memory ? "memorychip" : "lock.icloud")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.storageLabel).font(.system(size: 12, weight: .medium))
                        Text("Storage & sync").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.system(size: 10))
                }.foregroundStyle(Palette.text)
            }.buttonStyle(.plain)
            if let toast = model.toast { Text(toast).font(.system(size: 10)).foregroundStyle(Palette.mint).fixedSize(horizontal: false, vertical: true) }
            Divider().overlay(.white.opacity(0.08))
            HStack {
                Button("Try sample clips", action: onSamples).buttonStyle(.plain).foregroundStyle(Palette.secondary)
                Spacer()
                Menu {
                    Button("Lock & Clear Memory") { model.lock(); PreviewCache.shared.removeAll() }
                    Button("Clear History…", role: .destructive) { confirmClear = true }.disabled(model.isLocked)
                    Divider()
                    Button("Quit CopyTaste") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions")
            }.font(.system(size: 10))
        }.padding(20).frame(width: 340).foregroundStyle(Palette.text).background(Palette.background)
            .preferredColorScheme(.dark).tint(Palette.mint)
            .onAppear { trusted = PasteService.hasAccess }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = PasteService.hasAccess }
            .alert("Clear all history?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { model.clearHistory(); PreviewCache.shared.removeAll() }
            } message: { Text("Pinned entries are included. Cloud deletions propagate to other Macs.") }
            .alert("CopyTaste", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private func toggle(_ name: String, subtitle: String, symbol: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 4)
            Toggle(name, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini).accessibilityLabel(name)
        }
    }
}
