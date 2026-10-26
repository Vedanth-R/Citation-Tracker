import Foundation
import Testing
@testable import CiteKitCore

struct SourceSearchTests {
    static let response = #"{"message":{"items":[{"DOI":"10.1234/one","title":["Learning &amp; sharing"],"author":[{"given":"Jane","family":"Smith"}],"container-title":["Example Journal"],"published":{"date-parts":[[2025]]}},{"DOI":"10.1234/ONE","title":["Duplicate"]},{"title":["No identifier"]},{"DOI":"not-a-doi","title":["Invalid identifier"]},{"DOI":"10.1234/two","title":["Second result"]}]}}"#
    @Test func rankedResultsPreserveOrderAndDeduplicate() async throws {
        let client = HTTPClient { request in
            let url = try #require(request.url)
            #expect(url.host == "api.crossref.org")
            let parameters = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(parameters.first { $0.name == "query.bibliographic" }?.value == "Smith & learning 2025")
            #expect(parameters.first { $0.name == "rows" }?.value == "10")
            return Data(Self.response.utf8)
        }
        let results = try await SourceSearch(client: client).search("  Smith & learning\n2025 ")
        #expect(results.map(\.doi) == ["10.1234/one", "10.1234/two"])
        #expect(results.first?.title == "Learning & sharing")
        #expect(results.first?.authors == "Jane Smith")
        #expect(results.first?.year == 2025)
        #expect(results.first?.url.absoluteString == "https://doi.org/10.1234/one")
    }
    @Test func emptyAndOversizedQueriesDoNotRequestNetwork() async {
        let search = SourceSearch(client: HTTPClient { _ in
            Issue.record("Invalid input must not reach the network")
            return Data()
        })
        await #expect(throws: SourceSearchError.self) { try await search.search(" \n ") }
        await #expect(throws: SourceSearchError.self) { try await search.search(String(repeating: "a", count: 1001)) }
    }
    @Test func noMatchesIsDifferentFromInvalidResponseOrNetworkFailure() async throws {
        #expect(try SourceSearch.decode(Data(#"{"message":{"items":[]}}"#.utf8)).isEmpty)
        #expect(throws: SourceSearchError.self) { try SourceSearch.decode(Data(#"{"message":{}}"#.utf8)) }
        let search = SourceSearch(client: HTTPClient { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await search.search("A title") }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_LIVE_TESTS"] == "1"))
    func livePartialReferenceFindsKnownDOI() async throws {
        let results = try await SourceSearch().search("Piwowar sharing detailed research data increased citation rate 2007")
        #expect(results.contains { $0.doi.lowercased() == "10.1371/journal.pone.0000308" })
    }
}
