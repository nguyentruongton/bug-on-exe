import Foundation
import AppKit

let args = CommandLine.arguments
if args.count >= 3 && args[1] == "--extract-test" {
    let url = URL(fileURLWithPath: args[2])
    do {
        let payload = try ExeSwfExtractor.extract(from: url)
        let session = try ProjectorRunner.prepareForLaunch(fileURL: url)
        print("EXTRACT_TEST_OK: \(payload.signature) v\(payload.version) (\(payload.data.count) bytes) -> \(session.swfFileURL.path)")
        exit(0)
    } catch {
        fputs("EXTRACT_TEST_ERROR: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
