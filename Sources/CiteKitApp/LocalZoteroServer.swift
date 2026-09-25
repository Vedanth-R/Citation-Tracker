import Foundation
import Combine

struct LocalZoteroResources {
    var node: URL
    var server: URL
    var launcher: URL
    static func locate() -> LocalZoteroResources {
        if let resources = Bundle.main.resourceURL {
            let root = resources.appendingPathComponent("Zotero")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("managed-server.cjs").path) {
                return LocalZoteroResources(node: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/node"), server: root.appendingPathComponent("server"), launcher: root.appendingPathComponent("managed-server.cjs"))
            }
        }
        // SwiftPM development/tests only. Packaged apps always use their own resources.
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return LocalZoteroResources(node: project.appendingPathComponent(".build/node-v24.21.0-darwin-arm64/bin/node"), server: project.appendingPathComponent(".build/zotero-server"), launcher: project.appendingPathComponent("Support/Zotero/managed-server.cjs"))
    }
}
struct LocalZoteroConnection {
    let endpoint: URL
    let token: String
}
enum LocalZoteroError: LocalizedError {
    case missingResources, failedToStart, timedOut
    var errorDescription: String? {
        switch self {
        case .missingResources: return "This CiteKit build is missing its Zotero components. Reinstall a complete app build."
        case .failedToStart: return "Zotero could not start. Try again; other citation providers are still available."
        case .timedOut: return "Zotero took too long to start. Try again; other citation providers are still available."
        }
    }
}
@MainActor final class LocalZoteroServer: ObservableObject {
    static let shared = LocalZoteroServer()
    @Published private(set) var status = "Off"
    @Published private(set) var error: String?
    @Published private(set) var isReady = false
    private var process: Process?
    private var input: Pipe?
    private var connection: LocalZoteroConnection?
    private var startup: Task<LocalZoteroConnection, Error>?
    private var attempt = UUID()
    private let resources: LocalZoteroResources
    init(resources: LocalZoteroResources = .locate()) { self.resources = resources }
    var processIdentifier: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    func ensureRunning() async throws -> LocalZoteroConnection {
        if let connection, process?.isRunning == true { return connection }
        if let startup { return try await startup.value }
        let id = UUID(); attempt = id
        status = "Starting Zotero…"; error = nil; isReady = false
        let task = Task { try await launch(id: id) }
        startup = task
        do {
            let ready = try await task.value
            guard attempt == id else { throw CancellationError() }
            startup = nil; connection = ready; status = "Ready · runs automatically on this Mac"; isReady = true
            return ready
        } catch {
            if attempt == id {
                startup = nil; stopProcess(); isReady = false
                self.error = error.localizedDescription; status = "Zotero unavailable"
            }
            throw error
        }
    }
    func stop() {
        attempt = UUID(); startup?.cancel(); startup = nil
        stopProcess(); status = "Off"; error = nil; isReady = false
    }
    private func stopProcess() {
        let child = process
        process = nil; connection = nil
        try? input?.fileHandleForWriting.close(); input = nil
        if child?.isRunning == true { child?.terminate() }
    }
    private func launch(id: UUID) async throws -> LocalZoteroConnection {
        try Task.checkCancellation()
        guard attempt == id else { throw CancellationError() }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: resources.node.path), fm.fileExists(atPath: resources.server.appendingPathComponent("node_modules/koa/package.json").path), fm.fileExists(atPath: resources.launcher.path) else { throw LocalZoteroError.missingResources }
        let directory = fm.temporaryDirectory.appendingPathComponent("CiteKit-Zotero-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let readyFile = directory.appendingPathComponent("ready.json")
        let token = UUID().uuidString + UUID().uuidString
        let child = Process(); let pipe = Pipe()
        child.executableURL = resources.node
        child.arguments = [resources.launcher.path, resources.server.path, readyFile.path, String(ProcessInfo.processInfo.processIdentifier)]
        child.currentDirectoryURL = resources.server
        child.environment = ["PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory(), "NODE_CONFIG": "{\"host\":\"127.0.0.1\",\"port\":0}", "NODE_ENV": "production", "DEBUG_LEVEL": "0", "CITEKIT_ZOTERO_TOKEN": token]
        child.standardInput = pipe; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                guard let self, self.process === terminated, self.attempt == id else { return }
                self.process = nil; self.connection = nil; self.isReady = false
                self.error = "Zotero stopped unexpectedly. It will restart on the next lookup."
                self.status = "Zotero unavailable"
            }
        }
        try child.run()
        process = child; input = pipe
        struct Ready: Decodable { var port: Int; var pid: Int32 }
        for _ in 0..<150 {
            try Task.checkCancellation()
            guard attempt == id else { throw CancellationError() }
            guard child.isRunning else { throw LocalZoteroError.failedToStart }
            if let data = try? Data(contentsOf: readyFile), let ready = try? JSONDecoder().decode(Ready.self, from: data), ready.pid == child.processIdentifier, (1...65535).contains(ready.port) {
                let endpoint = URL(string: "http://127.0.0.1:\(ready.port)")!
                var request = URLRequest(url: endpoint.appendingPathComponent("citekit-health"), timeoutInterval: 2)
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LocalZoteroError.failedToStart }
                try Task.checkCancellation()
                return LocalZoteroConnection(endpoint: endpoint, token: token)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw LocalZoteroError.timedOut
    }
}
