import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ResolverOptions: Sendable {
    public var usePubMed = true
    public var useArxiv = true
    public var useISBN = true
    public var compareWebMetadata = true
    public var zoteroEndpoint: URL?
    public var zoteroAuthorizationToken: String?
    public var zoteroStartupIssue: String?
    public init() {}
    public static func validZoteroEndpoint(_ text: String) -> URL? {
        guard let u = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = u.host, u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, !u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("web"),
              u.scheme == "https" || (u.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else { return nil }
        return u.url
    }
}
public struct HTTPClient: Sendable {
    public var send: @Sendable (URLRequest) async throws -> Data
    public init(send: @escaping @Sendable (URLRequest) async throws -> Data = { try await HTTPClient.live($0) }) { self.send = send }
    public static func live(_ original: URLRequest) async throws -> Data {
        var request = original; request.timeoutInterval = 18
        request.setValue("CiteKit/0.2 (macOS citation assistant)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResolutionError.incomplete }
        if http.statusCode == 300 { throw ResolutionError.multipleResults }
        guard (200..<300).contains(http.statusCode) else { throw ResolutionError.unavailable(http.statusCode) }
        if response.expectedContentLength > 5_000_000 { throw ResolutionError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count > 5_000_000 { throw ResolutionError.tooLarge }
        }
        return data
    }
    func get(_ url: URL) async throws -> Data { try await send(URLRequest(url: url)) }
}
private final class XMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []
    init(_ name: String, _ attributes: [String: String]) { self.name = name.components(separatedBy: ":").last!; self.attributes = attributes }
    func all(_ name: String) -> [XMLNode] { children.flatMap { ($0.name == name ? [$0] : []) + $0.all(name) } }
    func first(_ name: String) -> XMLNode? { all(name).first }
    var value: String { text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
}
private final class XMLTree: NSObject, XMLParserDelegate {
    let root = XMLNode("root", [:])
    var stack: [XMLNode] = []
    func parse(_ data: Data) throws -> XMLNode {
        // Never interpret externally supplied entity declarations.
        if String(data: data, encoding: .utf8)?.range(of: "<!ENTITY", options: .caseInsensitive) != nil { throw ResolutionError.incomplete }
        stack = [root]
        let parser = XMLParser(data: data); parser.delegate = self; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw ResolutionError.incomplete }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let node = XMLNode(name, attributes); stack.last?.children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { for node in stack { node.text += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { stack.removeLast() }
}
public enum ProviderDecoders {
    static func mark(_ item: inout CitationItem, provider: String, confidence: Double = 0.9) {
        for key in MetadataMerger.values(item).keys { item.evidence[key] = FieldEvidence(provider, confidence) }
    }
    static func setDate(_ raw: String, on item: inout CitationItem) {
        if let match = WebMetadata.matches("^([0-9]{4})(?:[-/]([0-9]{1,2}))?(?:[-/]([0-9]{1,2}))?", raw).first {
            item.year = Int(match[1]); item.month = Int(match[2]); item.day = Int(match[3]); return
        }
        item.year = WebMetadata.matches("\\b((?:18|19|20|21)[0-9]{2})\\b", raw).first.flatMap { Int($0[1]) }
    }
    public static func pubmed(_ data: Data, expectedID: String) throws -> CitationItem {
        let root = try XMLTree().parse(data)
        guard let article = root.first("PubmedArticle"), article.first("PMID")?.value == expectedID, let title = article.first("ArticleTitle")?.value, !title.isEmpty else { throw ResolutionError.identifierMismatch }
        var item = CitationItem(title: title, url: "https://pubmed.ncbi.nlm.nih.gov/\(expectedID)/")
        item.pmid = expectedID; item.type = "article-journal"
        item.authors = article.all("Author").compactMap { node in
            if let organization = node.first("CollectiveName")?.value { return Creator(literal: organization) }
            guard let family = node.first("LastName")?.value else { return nil }
            return Creator(given: node.first("ForeName")?.value ?? node.first("Initials")?.value ?? "", family: family)
        }
        item.container = article.first("Journal")?.first("Title")?.value ?? ""
        if let date = article.first("Journal")?.first("PubDate") {
            item.year = date.first("Year").flatMap { Int($0.value) }
            if item.year == nil { setDate(date.first("MedlineDate")?.value ?? "", on: &item) }
            let month = date.first("Month")?.value ?? ""
            item.month = Int(month) ?? ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex(of: String(month.lowercased().prefix(3))).map { $0 + 1 }
            item.day = date.first("Day").flatMap { Int($0.value) }
        }
        item.volume = article.first("JournalIssue")?.first("Volume")?.value ?? ""
        item.issue = article.first("JournalIssue")?.first("Issue")?.value ?? ""
        item.pages = article.first("MedlinePgn")?.value ?? ""
        if let value = article.all("ArticleId").first(where: { $0.attributes["IdType"] == "doi" })?.value, case .doi(let doi) = SourceClassifier.classify(value) { item.doi = doi }
        mark(&item, provider: "PubMed", confidence: 0.95)
        return item
    }
    public static func arxiv(_ data: Data, expectedID: String) throws -> CitationItem {
        let root = try XMLTree().parse(data)
        guard let entry = root.first("entry"), let rawID = entry.first("id")?.value, case .arxiv(let returnedID) = SourceClassifier.classify(rawID), let title = entry.first("title")?.value, !title.isEmpty else { throw ResolutionError.incomplete }
        func base(_ id: String) -> String { id.replacingOccurrences(of: "v[0-9]+$", with: "", options: .regularExpression).lowercased() }
        guard base(returnedID) == base(expectedID), expectedID.range(of: "v[0-9]+$", options: .regularExpression) == nil || returnedID.lowercased() == expectedID.lowercased() else { throw ResolutionError.identifierMismatch }
        var item = CitationItem(title: title, url: "https://arxiv.org/abs/\(returnedID)")
        item.arxivID = returnedID; item.type = "article"; item.container = "arXiv"; item.publisher = "arXiv"
        item.authors = entry.all("author").compactMap { $0.first("name")?.value }.map(WebMetadata.person)
        setDate(entry.first("published")?.value ?? "", on: &item)
        // A linked journal DOI refers to another version and must not replace preprint metadata.
        if entry.first("doi") != nil { item.warnings.append("A published-version DOI is linked by arXiv. This citation describes the preprint version.") }
        mark(&item, provider: "arXiv")
        return item
    }
    public static func isbn(_ data: Data, expectedISBN: String, authorNames: [String: String] = [:]) throws -> CitationItem {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ResolutionError.incomplete }
        let book = root["ISBN:" + expectedISBN] as? [String: Any] ?? root
        guard let title = book["title"] as? String, !title.isEmpty else { throw ResolutionError.incomplete }
        let ids = book["identifiers"] as? [String: [String]] ?? [:]
        let returned = (ids["isbn_10"] ?? book["isbn_10"] as? [String] ?? []) + (ids["isbn_13"] ?? book["isbn_13"] as? [String] ?? [])
        guard let canonical = ISBNParser.canonical13(expectedISBN), returned.contains(where: { ISBNParser.canonical13($0) == canonical }) else { throw ResolutionError.identifierMismatch }
        var item = CitationItem(title: title, url: book["url"] as? String ?? "https://openlibrary.org/isbn/\(expectedISBN)")
        item.isbn = canonical; item.type = "book"
        let creators = book["authors"] as? [[String: String]] ?? []
        item.authors = creators.compactMap { $0["name"] ?? $0["key"].flatMap { authorNames[$0] } }.map(WebMetadata.person)
        if item.authors.count != creators.count { item.warnings.append("Some Open Library author records could not be retrieved. Review the author list.") }
        if let contributors = book["contributions"] as? [String], !contributors.isEmpty { item.warnings.append("This edition lists additional contributors: " + contributors.joined(separator: "; ") + ". Check their author/editor roles.") }
        item.publisher = (book["publishers"] as? [String] ?? (book["publishers"] as? [[String: String]] ?? []).compactMap { $0["name"] }).joined(separator: "; ")
        setDate(book["publish_date"] as? String ?? "", on: &item)
        mark(&item, provider: "Open Library", confidence: 0.85)
        return item
    }

    public static func zotero(_ data: Data, sourceURL: URL) throws -> CitationItem {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], items.count == 1 else { throw ResolutionError.multipleResults }
        let z = items[0]
        guard let title = z["title"] as? String, !title.isEmpty else { throw ResolutionError.incomplete }
        var item = CitationItem(title: title, url: z["url"] as? String ?? sourceURL.absoluteString)
        item.type = ["journalArticle": "article-journal", "book": "book", "newspaperArticle": "article-newspaper", "preprint": "article"][z["itemType"] as? String ?? ""] ?? "webpage"
        item.authors = (z["creators"] as? [[String: Any]] ?? []).filter { ($0["creatorType"] as? String ?? "author") == "author" }.map { creator in
            if creator["fieldMode"] as? Int == 1 || creator["name"] != nil { return Creator(literal: creator["name"] as? String ?? creator["lastName"] as? String ?? "") }
            return Creator(given: creator["firstName"] as? String ?? "", family: creator["lastName"] as? String ?? "")
        }
        item.container = z["publicationTitle"] as? String ?? z["websiteTitle"] as? String ?? ""
        item.publisher = z["publisher"] as? String ?? ""
        setDate(z["date"] as? String ?? "", on: &item)
        item.volume = z["volume"] as? String ?? ""; item.issue = z["issue"] as? String ?? ""; item.pages = z["pages"] as? String ?? ""
        if let raw = z["DOI"] as? String, case .doi(let doi) = SourceClassifier.classify(raw) { item.doi = doi }
        if let raw = z["ISBN"] as? String { item.isbn = ISBNParser.normalize(raw) }
        mark(&item, provider: "Zotero", confidence: 0.85)
        return item
    }
}
