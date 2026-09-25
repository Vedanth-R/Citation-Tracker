import Foundation
import Darwin
import Testing
import CiteKitCore
@testable import CiteKitApp

@Suite(.serialized) @MainActor struct LocalZoteroServerTests {
    private func resources() -> LocalZoteroResources {
        if let app = ProcessInfo.processInfo.environment["CITEKIT_PACKAGED_ZOTERO_APP"] {
            let root = URL(fileURLWithPath: app)
            return LocalZoteroResources(node: root.appendingPathComponent("Contents/Helpers/node"), server: root.appendingPathComponent("Contents/Resources/Zotero/server"), launcher: root.appendingPathComponent("Contents/Resources/Zotero/managed-server.cjs"))
        }
        return .locate()
    }
    private func exited(_ pid: Int32) async -> Bool {
        for _ in 0..<30 {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
    @Test func missingComponentsProduceActionableError() async {
        let missing = URL(fileURLWithPath: "/nonexistent-citekit-test")
        let service = LocalZoteroServer(resources: LocalZoteroResources(node: missing, server: missing, launcher: missing))
        await #expect(throws: LocalZoteroError.self) { try await service.ensureRunning() }
        #expect(service.isReady == false)
        #expect(service.error?.contains("missing its Zotero components") == true)
        service.stop(); #expect(service.status == "Off")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_MANAGED_ZOTERO_TESTS"] == "1"))
    func automaticStartConcurrentRequestsAuthenticationAndStop() async throws {
        let service = LocalZoteroServer(resources: resources())
        defer { service.stop() }
        async let first = service.ensureRunning()
        async let second = service.ensureRunning()
        let (a, b) = try await (first, second)
        #expect(a.endpoint == b.endpoint); #expect(a.token == b.token); #expect(service.isReady)
        #expect(a.endpoint.host == "127.0.0.1")
        let pid = try #require(service.processIdentifier)
        let (_, rejected) = try await URLSession.shared.data(from: a.endpoint.appendingPathComponent("citekit-health"))
        #expect((rejected as? HTTPURLResponse)?.statusCode == 401)
        var request = URLRequest(url: a.endpoint.appendingPathComponent("citekit-health"))
        request.setValue("Bearer " + a.token, forHTTPHeaderField: "Authorization")
        let (_, accepted) = try await URLSession.shared.data(for: request)
        #expect((accepted as? HTTPURLResponse)?.statusCode == 200)
        service.stop()
        #expect(await exited(pid)); #expect(!service.isReady)
        let restarted = try await service.ensureRunning()
        #expect(restarted.token != a.token); #expect(service.processIdentifier != pid)
        let nextPID = try #require(service.processIdentifier)
        service.stop(); #expect(await exited(nextPID))
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_MANAGED_ZOTERO_TESTS"] == "1"))
    func disablingDuringStartupLeavesNoProcess() async throws {
        let service = LocalZoteroServer(resources: resources())
        let start = Task { try await service.ensureRunning() }
        try await Task.sleep(nanoseconds: 40_000_000)
        let pid = service.processIdentifier
        service.stop()
        await #expect(throws: (any Error).self) { try await start.value }
        #expect(service.status == "Off"); #expect(service.processIdentifier == nil)
        if let pid { #expect(await exited(pid)) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_MANAGED_ZOTERO_TESTS"] == "1"))
    func automaticallyStartedServerResolvesRealCitation() async throws {
        let service = LocalZoteroServer(resources: resources())
        defer { service.stop() }
        let connection = try await service.ensureRunning()
        var options = ResolverOptions(); options.zoteroEndpoint = connection.endpoint; options.zoteroAuthorizationToken = connection.token
        let item = try await CitationResolver(options: options).resolve("https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0000308")
        #expect(item.checks?.contains { $0.provider == "Zotero" && $0.status == .extracted } == true)
        #expect(item.doi == "10.1371/journal.pone.0000308")
        #expect(!(try CitationFormatter().format(item, style: .apa).full.isEmpty))
    }
}
