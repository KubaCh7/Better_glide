import Foundation

/// Runs system command-line tools (hdiutil, codesign, security, …) on behalf of the app,
/// so the user never has to open Terminal.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
