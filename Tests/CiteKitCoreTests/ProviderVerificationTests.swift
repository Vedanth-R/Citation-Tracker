import Foundation
import Testing
@testable import CiteKitCore

struct ProviderVerificationTests {
    static let pubmed = """
    <PubmedArticleSet><PubmedArticle><MedlineCitation><PMID>12345</PMID><Article><ArticleTitle>Learning <i>together</i></ArticleTitle><Journal><Title>Journal of Learning</Title><JournalIssue><Volume>12</Volume><Issue>2</Issue><PubDate><Year>2025</Year><Month>Mar</Month><Day>2</Day></PubDate></JournalIssue></Journal><AuthorList><Author><LastName>Smith</LastName><ForeName>Jane A.</ForeName></Author><Author><CollectiveName>Research Council</CollectiveName></Author></AuthorList><Pagination><MedlinePgn>41-52</MedlinePgn></Pagination></Article></MedlineCitation><PubmedData><ArticleIdList><ArticleId IdType="doi">10.1234/example</ArticleId></ArticleIdList></PubmedData></PubmedArticle></PubmedArticleSet>
    """
    static let arxiv = """
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom"><entry><id>http://arxiv.org/abs/2401.12345v2</id><title> Learning\n together </title><published>2024-01-23T00:00:00Z</published><author><name>Jane Smith</name></author><arxiv:doi>10.1234/journal</arxiv:doi></entry></feed>
    """
    static let book = #"{"ISBN:9780306406157":{"title":"A book","url":"https://openlibrary.org/books/OL1M","authors":[{"name":"Jane Smith"}],"publishers":[{"name":"Academic Press"}],"publish_date":"March 1980","identifiers":{"isbn_13":["9780306406157"]}}}"#
    static let zotero = #"[{"itemType":"journalArticle","title":"Learning together","creators":[{"creatorType":"author","firstName":"Jane","lastName":"Smith"},{"creatorType":"editor","firstName":"Editor","lastName":"Ignored"}],"publicationTitle":"Journal of Learning","date":"2025-03-02","DOI":"10.1234/example","volume":"12","issue":"2","pages":"41-52"}]"#
    static let crossref = #"{"message":{"title":["Learning together"],"DOI":"10.1234/example","type":"journal-article","author":[{"given":"Jane","family":"Smith"}],"container-title":["Journal of Learning"],"published":{"date-parts":[[2025]]}}}"#
    func source(year: Int = 2025) -> CitationItem {
        var item = CitationItem(title: "Learning together", url: "https://example.org/article")
        item.authors = [Creator(given: "Jane", family: "Smith")]; item.year = year; item.container = "Journal of Learning"; item.type = "article-journal"; item.doi = "10.1234/example"
        return item
    }
    @Test func identifiersAndChecksums() {
        #expect(SourceClassifier.classify("<https://pubmed.ncbi.nlm.nih.gov/12345/?utm_source=x>") == .pmid("12345"))
        #expect(SourceClassifier.classify("PMID: 12345") == .pmid("12345"))
        #expect(SourceClassifier.classify("12345") == .text("12345"))
        #expect(SourceClassifier.classify("https://arxiv.org/pdf/2401.12345v2.pdf") == .arxiv("2401.12345v2"))
        #expect(SourceClassifier.classify("arXiv:hep-th/9901001") == .arxiv("hep-th/9901001"))
        #expect(SourceClassifier.classify("ISBN: 978-0-306-40615-7") == .isbn("9780306406157"))
        #expect(ISBNParser.normalize("0-8044-2957-X") == "080442957X")
        #expect(ISBNParser.normalize("9780306406158") == nil)
        #expect(ISBNParser.normalize("0804429570") == nil)
        #expect(SourceClassifier.classify("“https://example.org/article”") == .url(URL(string: "https://example.org/article")!))
        #expect(SourceClassifier.classify("www.example.org/article") == .url(URL(string: "https://www.example.org/article")!))
    }
    @Test func parsesPubmedAndRejectsWrongRecord() throws {
        let item = try ProviderDecoders.pubmed(Data(Self.pubmed.utf8), expectedID: "12345")
        #expect(item.title == "Learning together"); #expect(item.month == 3); #expect(item.day == 2)
        #expect(item.authors[1].literal == "Research Council"); #expect(item.doi == "10.1234/example")
        #expect(throws: (any Error).self) { try ProviderDecoders.pubmed(Data(Self.pubmed.utf8), expectedID: "99999") }
    }
    @Test func arxivKeepsPreprintVersion() throws {
        let item = try ProviderDecoders.arxiv(Data(Self.arxiv.utf8), expectedID: "2401.12345")
        #expect(item.arxivID == "2401.12345v2"); #expect(item.year == 2024); #expect(item.doi == nil)
        #expect(item.warnings.contains { $0.contains("published-version") })
        #expect(throws: (any Error).self) { try ProviderDecoders.arxiv(Data(Self.arxiv.utf8), expectedID: "2401.12345v1") }
        #expect(throws: (any Error).self) { try ProviderDecoders.arxiv(Data(Self.arxiv.utf8), expectedID: "2401.99999") }
    }
    @Test func editionLookupMatchesISBN10And13() throws {
        let data = Data(#"{"title":"A book","isbn_10":["0306406152"],"authors":[{"key":"/authors/OL1A"}],"publishers":["Academic Press"],"publish_date":"1981"}"#.utf8)
        let item = try ProviderDecoders.isbn(data, expectedISBN: "9780306406157", authorNames: ["/authors/OL1A": "Jane Smith"])
        #expect(item.isbn == "9780306406157"); #expect(item.authors.first?.family == "Smith"); #expect(item.year == 1981)
        #expect(ISBNParser.canonical13("0306406152") == "9780306406157")
        #expect(throws: (any Error).self) { try ProviderDecoders.isbn(data, expectedISBN: "9780140328721") }
    }
    @Test func parsesBooksAndZotero() throws {
        let book = try ProviderDecoders.isbn(Data(Self.book.utf8), expectedISBN: "9780306406157")
        #expect(book.type == "book"); #expect(book.year == 1980); #expect(book.publisher == "Academic Press")
        #expect(try CitationFormatter().format(book, style: .apa).full.contains("Academic Press"))
        let z = try ProviderDecoders.zotero(Data(Self.zotero.utf8), sourceURL: URL(string: "https://example.org")!)
        #expect(z.authors.count == 1); #expect(z.day == 2); #expect(z.container == "Journal of Learning")
        #expect(throws: (any Error).self) { try ProviderDecoders.zotero(Data("[]".utf8), sourceURL: URL(string: "https://example.org")!) }
    }
    @Test func preservesConflictsAndUserChoices() throws {
        var web = source(year: 2024); web.title = "Another title"
        var item = try MetadataMerger.merge([MetadataCandidate(source(), provider: "Crossref"), MetadataCandidate(web, provider: "Webpage")], checks: [ProviderCheck("Crossref", .matched, "DOI matched")])
        #expect(item.conflicts?.count == 2); #expect(item.year == 2025); #expect(item.confidence.level == .medium)
        MetadataMerger.select(field: "date", provider: "Webpage", in: &item)
        #expect(item.year == 2024); #expect(item.conflicts?.first { $0.field == "date" }?.reviewed == true)
        #expect(item.confidence.level == .medium)
        let restored = try JSONDecoder().decode(CitationItem.self, from: JSONEncoder().encode(item))
        #expect(restored.year == 2024); #expect(restored.conflicts?.count == 2)
    }
    @Test func compatibleNamesAndDatePrecisionAreNotConflicts() throws {
        var richer = source(); richer.authors[0].given = "Jane A."; richer.month = 3; richer.day = 2
        let item = try MetadataMerger.merge([MetadataCandidate(source(), provider: "Crossref"), MetadataCandidate(richer, provider: "PubMed")], checks: [ProviderCheck("Crossref", .matched, "DOI matched")])
        #expect(item.conflicts?.isEmpty == true); #expect(item.authors[0].given == "Jane A."); #expect(item.month == 3)
        var other = richer; other.authors[0].given = "Jane B."
        let conflict = try MetadataMerger.merge([MetadataCandidate(richer, provider: "Crossref"), MetadataCandidate(other, provider: "PubMed")], checks: [])
        #expect(conflict.conflicts?.contains { $0.field == "authors" } == true)
    }
    @Test func confidenceExplainsVerificationGaps() throws {
        var item = source(); item.doi = nil; item.evidence["title"] = FieldEvidence("JSON-LD", 0.7)
        #expect(item.confidence.level == .medium)
        #expect(item.confidence.issues.contains { $0.contains("No Crossref") })
        item.checks = [ProviderCheck("Zotero", .extracted, "Translated")]
        #expect(item.confidence.level == .high)
        #expect(item.confidence.issues.contains { $0.contains("not independent") })
        item.checks = [ProviderCheck("PubMed", .matched, "PMID matched")]; item.pmid = "12345"
        #expect(item.confidence.level == .high)
        item.year = nil; item.authors = []
        #expect(item.confidence.level == .low)
        item = source(); item.checks = [ProviderCheck("Crossref", .matched, "DOI matched"), ProviderCheck("Zotero", .unavailable, "Server offline")]
        #expect(item.confidence.level == .high)
        #expect(item.confidence.issues.contains { $0.contains("Server offline") })
    }
    @Test func legacyHistoryRemainsDecodable() throws {
        let data = try JSONEncoder().encode(source())
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["checks", "conflicts", "pmid", "isbn", "arxivID"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(CitationItem.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.title == "Learning together"); #expect(restored.conflicts == nil)
    }
    @Test func pipelineComparesProvidersAndSurvivesZoteroFailure() async throws {
        var options = ResolverOptions(); options.zoteroEndpoint = URL(string: "http://127.0.0.1:1969")
        let client = HTTPClient { request in
            if request.url?.host == "api.crossref.org" { return Data(Self.crossref.utf8) }
            if request.url?.host == "127.0.0.1" { throw URLError(.cannotConnectToHost) }
            return Data("<meta name='citation_title' content='Learning together'><meta name='citation_author' content='Jane Smith'><meta name='citation_publication_date' content='2024'><meta name='citation_journal_title' content='Journal of Learning'><meta name='citation_doi' content='10.1234/example'>".utf8)
        }
        let item = try await CitationResolver(options: options, client: client).resolve("https://example.org/article")
        #expect(item.conflicts?.contains { $0.field == "date" } == true)
        #expect(item.checks?.contains { $0.provider == "Zotero" && $0.status == .unavailable } == true)
        #expect(item.confidence.level == .medium)
    }
    @Test func zoteroPostAndFallbackWhenPageBlocked() async throws {
        var options = ResolverOptions(); options.zoteroEndpoint = URL(string: "http://127.0.0.1:1969")
        let client = HTTPClient { request in
            if request.url?.path == "/web" {
                #expect(request.httpMethod == "POST"); #expect(String(data: request.httpBody!, encoding: .utf8) == "https://example.org/article")
                return Data(Self.zotero.utf8)
            }
            if request.url?.host == "api.crossref.org" { return Data(Self.crossref.utf8) }
            throw ResolutionError.unavailable(403)
        }
        let item = try await CitationResolver(options: options, client: client).resolve("https://example.org/article")
        #expect(item.title == "Learning together"); #expect(item.checks?.contains { $0.provider == "Zotero" && $0.status == .extracted } == true)
        #expect(item.confidence.level != .verified)
    }
    @Test func disabledProviderAndCancellationMakeNoFallbackLookups() async throws {
        var options = ResolverOptions(); options.usePubMed = false
        let client = HTTPClient { _ in Issue.record("Unexpected network access"); throw URLError(.cancelled) }
        await #expect(throws: (any Error).self) { try await CitationResolver(options: options, client: client).resolve("PMID: 12345") }
        let cancelledClient = HTTPClient { _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) { try await CitationResolver(client: cancelledClient).resolve("https://example.org") }
    }
    @Test func zoteroEndpointValidation() {
        #expect(ResolverOptions.validZoteroEndpoint("http://127.0.0.1:1969") != nil)
        #expect(ResolverOptions.validZoteroEndpoint("https://zotero.example.org") != nil)
        #expect(ResolverOptions.validZoteroEndpoint("http://remote.example.org") == nil)
        #expect(ResolverOptions.validZoteroEndpoint("https://user:secret@example.org") == nil)
        #expect(ResolverOptions.validZoteroEndpoint("file:///tmp/server") == nil)
        #expect(ResolverOptions.validZoteroEndpoint("http://127.0.0.1:1969/web") == nil)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_LIVE_TESTS"] == "1"))
    func liveAdditionalProviders() async throws {
        var options = ResolverOptions(); options.compareWebMetadata = false
        let resolver = CitationResolver(options: options)
        let pubmed = try await resolver.resolve("PMID: 31452104")
        #expect(pubmed.pmid == "31452104"); #expect(!pubmed.title.isEmpty)
        let book = try await resolver.resolve("ISBN: 9780306406157")
        #expect(book.isbn == "9780306406157"); #expect(!book.title.isEmpty)
        let preprint = try await resolver.resolve("arXiv: 1706.03762")
        #expect(preprint.arxivID?.hasPrefix("1706.03762") == true)
        #expect(preprint.title.lowercased().contains("attention"))
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CITEKIT_ZOTERO_LIVE_TESTS"] == "1"))
    func liveZoteroPipeline() async throws {
        var options = ResolverOptions()
        options.zoteroEndpoint = URL(string: "http://127.0.0.1:1969")
        let item = try await CitationResolver(options: options).resolve("https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0000308")
        #expect(item.doi?.lowercased() == "10.1371/journal.pone.0000308")
        #expect(item.checks?.contains { $0.provider == "Zotero" && $0.status == .extracted } == true)
        #expect(item.checks?.contains { $0.provider == "Crossref" && $0.status == .matched } == true)
        #expect(!item.authors.isEmpty)
        #expect(!(try CitationFormatter().format(item, style: .apa).full.isEmpty))
    }

}
