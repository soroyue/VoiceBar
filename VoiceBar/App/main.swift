import AppKit

let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")

func writeLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    fputs(line, stderr)
    fflush(stderr)
    do {
        let handle = try FileHandle(forWritingTo: logPath)
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    } catch {
        try? line.write(to: logPath, atomically: true, encoding: .utf8)
    }
}

writeLog("main: starting")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Menu bar app — no Dock icon, proper status item behavior
let delegate = AppDelegate()
app.delegate = delegate
writeLog("main: calling app.run()")
app.run()
writeLog("main: app.run() returned")
