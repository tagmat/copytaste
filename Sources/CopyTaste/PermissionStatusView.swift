import AppKit
import SwiftUI

struct PermissionStatusView: View {
    let isDemo: Bool
    @State private var accessibilityAllowed: Bool?
    @State private var clipboardStatus = "Checking…"

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Accessibility", systemImage: "accessibility")
                    .help("Required for Paste on selection.")
                Spacer()
                Text(accessibilityStatus).foregroundStyle(Palette.secondary)
                if accessibilityAllowed == false && !isDemo {
                    Button("Allow…") { PasteService.requestAccess() }
                        .controlSize(.small)
                        .accessibilityLabel("Allow Accessibility for direct paste")
                }
            }
            HStack {
                Label("Clipboard access", systemImage: "clipboard")
                    .help("System setting for reading clips from other apps.")
                Spacer()
                Text(isDemo ? "Sample session" : clipboardStatus)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .font(.system(size: 11))
        .task {
            guard !isDemo else { return }
            while !Task.isCancelled {
                refresh()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    private var accessibilityStatus: String {
        if isDemo { return "Sample session" }
        switch accessibilityAllowed {
        case true?: return "Allowed"
        case false?: return "Not granted"
        case nil: return "Checking…"
        }
    }

    private func refresh() {
        accessibilityAllowed = PasteService.hasAccess
        guard #available(macOS 15.4, *) else {
            clipboardStatus = "Status unavailable"
            return
        }
        switch NSPasteboard.general.accessBehavior {
        case .default: clipboardStatus = "System default"
        case .ask: clipboardStatus = "Ask"
        case .alwaysAllow: clipboardStatus = "Allowed"
        case .alwaysDeny: clipboardStatus = "Blocked"
        @unknown default: clipboardStatus = "Status unavailable"
        }
    }
}
