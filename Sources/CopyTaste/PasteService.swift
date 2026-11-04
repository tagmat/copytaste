import AppKit
import ApplicationServices
import Carbon
import CopyTasteCore

struct PasteDestination: Equatable {
    let processID: pid_t
    let name: String
}

enum PasteOutcome: Equatable {
    case pasted, copied, permissionRequired, destinationChanged, failed
}

@MainActor
final class PasteService {
    private let trusted: () -> Bool
    private let secureInput: () -> Bool
    private let frontmostPID: () -> pid_t?
    private let activate: (pid_t) -> Bool
    private let send: @MainActor (pid_t) -> Void
    private let settle: () async -> Void

    init(trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         activate: @escaping (pid_t) -> Bool = { NSRunningApplication(processIdentifier: $0)?.activate() ?? false },
         send: @escaping @MainActor (pid_t) -> Void = PasteService.sendCommandV,
         settle: @escaping () async -> Void = { try? await Task.sleep(for: .milliseconds(120)) }) {
        self.trusted = trusted; self.secureInput = secureInput; self.frontmostPID = frontmostPID
        self.activate = activate; self.send = send; self.settle = settle
    }

    func perform(copy: () -> Bool, destination: PasteDestination?, automatic: Bool, demo: Bool,
                 stillValid: () -> Bool = { true }) async -> PasteOutcome {
        guard stillValid(), copy() else { return .failed }
        guard automatic, !demo else { return .copied }
        guard trusted() else { return .permissionRequired }
        guard !secureInput(), let destination, destination.processID != ProcessInfo.processInfo.processIdentifier,
              activate(destination.processID) else { return .copied }
        await settle()
        guard stillValid(), trusted(), !secureInput(), frontmostPID() == destination.processID else { return .destinationChanged }
        send(destination.processID)
        return .pasted
    }

    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func sendCommandV(to processID: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processID)
        up.postToPid(processID)
    }
}
