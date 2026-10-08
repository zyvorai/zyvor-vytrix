// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin

/// Runs the bundled, dependency-free collector (vytrix.py) on loopback with a random token that only
/// this app knows. The token lives in memory: it is never written to disk, logged, or put in a URL.
final class CollectorProcess {
    struct Endpoint { let url: URL; let token: String }
    enum Failure: LocalizedError {
        case noPython, noScript, launch(String)
        var errorDescription: String? {
            switch self {
            case .noPython: return "Vytrix needs Python 3.10 or newer to run its collector. Install it (for example `brew install python`) or connect to a collector running elsewhere."
            case .noScript: return "The bundled collector (vytrix.py) is missing from the app."
            case .launch(let m): return "The collector would not start: \(m)"
            }
        }
    }

    private var process: Foundation.Process?

    /// First interpreter that is Python 3.10+. The system /usr/bin/python3 is often older.
    static func findPython() -> URL? {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let p = Foundation.Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["-c", "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                p.waitUntilExit()
                if p.terminationStatus == 0 { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }

    static func scriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "vytrix", withExtension: "py") { return bundled }
        if let override = ProcessInfo.processInfo.environment["VYTRIX_AGENT"] { return URL(fileURLWithPath: override) }
        return nil
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return got == 0 ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }

    func start() throws -> Endpoint {
        stop()
        guard let python = Self.findPython() else { throw Failure.noPython }
        guard let script = Self.scriptURL() else { throw Failure.noScript }
        guard let port = Self.freePort() else { throw Failure.launch("no free local port") }
        let token = Self.randomToken()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vytrix")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let p = Foundation.Process()
        p.executableURL = python
        p.arguments = [script.path, "--bind", "127.0.0.1", "--port", String(port),
                       "--database", support.appendingPathComponent("history.sqlite").path, "--interval", "2"]
        var env = ProcessInfo.processInfo.environment
        env["VYTRIX_TOKEN"] = token
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw Failure.launch(error.localizedDescription) }
        process = p
        return Endpoint(url: URL(string: "http://127.0.0.1:\(port)")!, token: token)
    }

    func stop() {
        guard let p = process, p.isRunning else { process = nil; return }
        p.terminate()
        process = nil
    }

    deinit { stop() }
}
