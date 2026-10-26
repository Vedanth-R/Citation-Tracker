import Foundation
import Testing
import CiteKitCore
@testable import CiteKitApp

struct StartupTests {
    @Test func disabledProvidersAreNotContacted() {
        var options = ResolverOptions()
        options.usePubMed = false; options.useArxiv = false; options.useISBN = false
        #expect(StartupProbe.endpoints(options).map(\.name) == ["Crossref"])
        #expect(StartupProbe.endpoints(ResolverOptions()).count == 4)
    }
    @Test func reachableRequiresSuccessAndExpectedResponse() throws {
        let endpoint = try #require(StartupProbe.endpoints(ResolverOptions()).first)
        #expect(StartupProbe.reachable(endpoint, data: Data(#"{"message":{}}"#.utf8), status: 200))
        #expect(!StartupProbe.reachable(endpoint, data: Data(#"{"message":{}}"#.utf8), status: 503))
        #expect(!StartupProbe.reachable(endpoint, data: Data("<html>Network login required</html>".utf8), status: 200))
        #expect(!StartupProbe.reachable(endpoint, data: Data(), status: 200))
    }
    @Test func bundledFormattersAreReadyWithoutNetwork() {
        #expect(StartupProbe.formatting().available)
    }
    @MainActor @Test func dismissalDoesNotDiscardCheckResultsOrReopen() {
        let controller = StartupController()
        controller.dismiss()
        controller.record(StartupCheck(name: "Offline provider", available: false))
        controller.show()
        #expect(controller.dismissed)
        #expect(controller.checks.count == 1)
        #expect(!controller.checks[0].available)
    }
}

struct StartupLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_LIVE_TESTS"] == "1"))
    func probesFinishWithoutBlockingOnUnavailableServices() async {
        let start = ContinuousClock.now
        let checks = await StartupProbe.run(ResolverOptions())
        #expect(checks.count == 4)
        #expect(start.duration(to: .now) < .seconds(10))
        for check in checks { print("Startup probe: \(check.name) = \(check.available)") }
    }
}
