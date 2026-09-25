import Foundation
import Testing
@testable import CiteKitCore

struct CiteKitCoreTests {
    func sample() -> CitationItem {
        var item = CitationItem(title: "Learning together", url: "https://doi.org/10.1234/example")
        item.type = "article-journal"; item.authors = [Creator(given: "Jane", family: "Smith")]
        item.year = 2025; item.container = "Journal of Learning"; item.volume = "12"; item.issue = "2"; item.pages = "41–52"; item.doi = "10.1234/example"
        return item
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_LIVE_TESTS"] == "1"))
    func liveCrossrefLookup() async throws {
        let item = try await CitationResolver().resolve("10.1038/nphys1170")
        #expect(item.doi?.lowercased() == "10.1038/nphys1170")
        #expect(!item.title.isEmpty)
        #expect(!item.authors.isEmpty)
        #expect(!(try CitationFormatter().format(item, style: .apa).full.isEmpty))
    }
    @Test func testDOIAndURLClassification() {
        #expect(SourceClassifier.classify("https://doi.org/10.1038/example") == .doi("10.1038/example"))
        #expect(SourceClassifier.classify("https://doi.org/10.1038/example?utm_source=test#ref") == .doi("10.1038/example"))
        #expect(SourceClassifier.classify("doi: 10.1234/example") == .doi("10.1234/example"))
        #expect(SourceClassifier.classify("https://example.org/article?id=42&utm_source=test#section") == .url(URL(string: "https://example.org/article?id=42")!))
        #expect(SourceClassifier.classify("A quote mentions 10.1234/example in context") == .text("A quote mentions 10.1234/example in context"))
        #expect(SourceClassifier.classify("file:///tmp/private.txt") == .text("file:///tmp/private.txt"))
    }
    @Test func testCSLAPA() throws {
        let result = try CitationFormatter().format(sample(), style: .apa, page: "42")
        #expect(result.full == "Smith, J. (2025). Learning together. Journal of Learning, 12(2), 41–52. https://doi.org/10.1234/example")
        #expect(result.inText == "(Smith, 2025, p. 42)")
        #expect(result.narrative == "Smith (2025, p. 42)")
    }
    @Test func testCSLMLA() throws {
        let result = try CitationFormatter().format(sample(), style: .mla, page: "42")
        #expect(result.inText == "(Smith 42)")
        #expect(result.full.contains("Smith, Jane."))
        #expect(result.full.contains("Learning Together"))
        #expect(result.full.contains("vol. 12"))
    }
    @Test func testMultipleAuthors() throws {
        var item = sample()
        item.authors.append(Creator(given: "John", family: "Jones"))
        #expect(try CitationFormatter().format(item, style: .apa).inText == "(Smith & Jones, 2025)")
        item.authors.append(Creator(given: "Alex", family: "Lee"))
        #expect(try CitationFormatter().format(item, style: .apa, page: "42–43").inText == "(Smith et al., 2025, pp. 42–43)")
        #expect(try CitationFormatter().format(item, style: .mla).inText == "(Smith et al.)")
    }
    @Test func testMissingDateAndOrganization() throws {
        var item = sample(); item.year = nil; item.authors = [Creator(literal: "Research Council")]
        #expect(try CitationFormatter().format(item, style: .apa).inText == "(Research Council, n.d.)")
        #expect(item.confidence.level == .low)
        item.authors = []
        #expect(!(try CitationFormatter().format(item, style: .apa).full.isEmpty))
    }
    @Test func testCrossrefNormalization() throws {
        let fixture = #"{"message":{"title":["A &amp; B"],"DOI":"10.1234/ABC","type":"journal-article","author":[{"given":"Jane","family":"Smith"}],"container-title":["Nature"],"published":{"date-parts":[[2025,3,2]]}}}"#
        let item = try CitationResolver.decodeCrossref(Data(fixture.utf8))
        #expect(item.title == "A & B"); #expect(item.year == 2025); #expect(item.month == 3)
        #expect(item.identity == "doi:10.1234/abc"); #expect(item.confidence.level == .verified)
        #expect(item.evidence["title"]?.provider == "Crossref")
    }
    @Test func testWebMetadataPriorityAndIncompleteHealth() throws {
        let html = #"<title>Fallback</title><meta content='Wrong title' property='og:title'><meta name='citation_author' content='Jane Smith'><script type="application/ld+json">{"@graph":[{"@type":"Article","headline":"Structured title","datePublished":"2024-02-03","author":{"@type":"Organization","name":"Research Council"}}]}</script>"#
        let item = try WebMetadata.extract(html, url: URL(string: "https://example.org")!)
        #expect(item.title == "Structured title"); #expect(item.authors.first?.literal == "Research Council")
        #expect(item.year == 2024); #expect(item.day == 3)
        #expect(item.confidence.level != .verified); #expect(!(item.confidence.issues.isEmpty))
        #expect(throws: (any Error).self) { try WebMetadata.extract("<html>No metadata</html>", url: URL(string: "https://example.org")!) }
    }
    @Test func testBibTeXEscapingAndRoundTrip() throws {
        var item = sample(); item.title = "A & B_{test}"
        #expect(CitationFormatter().bibtex(item).contains("A \\& B\\_\\{test\\}"))
        item.authors = [Creator(literal: "Research Council")]
        #expect(CitationFormatter().bibtex(item).contains("author = {{Research Council}}"))
        let restored = try JSONDecoder().decode(CitationItem.self, from: JSONEncoder().encode(item))
        #expect(restored.identity == item.identity)
    }
}
