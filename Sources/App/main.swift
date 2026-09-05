import AppKit

if CommandLine.arguments.contains("--self-check") {
    _ = NSApplication.shared
    var failures: [String] = []
    do { try SelfCheck.run() } catch { failures.append(error.localizedDescription) }
    do { try AppSelfCheck.run() } catch { failures.append(error.localizedDescription) }
    if failures.isEmpty { exit(0) }
    failures.forEach { fputs("Self-check failed: \($0)\n", stderr) }
    exit(1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
