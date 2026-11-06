import AppKit
import Foundation
if CommandLine.arguments.contains("--read") {
    let board = NSPasteboard(name: .init(CommandLine.arguments[2]))
    let path = CommandLine.arguments[3]
    let direct = (try? Data(contentsOf: URL(fileURLWithPath: path))) != nil
    let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    let bytes = urls?.first.flatMap { try? Data(contentsOf: $0) }
    let result: [String: Any] = ["directRead": direct, "urlReceived": urls?.first != nil, "pasteboardRead": bytes == Data("Synthetic sandbox transfer".utf8)]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    exit(bytes == Data("Synthetic sandbox transfer".utf8) && !direct ? 0 : 1)
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-sandbox-fixture-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: directory) }
let file = directory.appendingPathComponent("fixture.txt")
try Data("Synthetic sandbox transfer".utf8).write(to: file)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
let board = NSPasteboard(name: .init("net.tagmat.copytaste.sandbox-probe." + UUID().uuidString))
defer { board.releaseGlobally() }
board.clearContents()
guard board.writeObjects([FilePasteboardWriter(url: file)]) else { exit(3) }
let process = Process()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
process.arguments = ["--read", board.name.rawValue, file.path]
try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
