import Foundation
public enum ResolutionError: LocalizedError {
    case unrecognized, unavailable(Int), incomplete, tooLarge, multipleResults, identifierMismatch, disabled(String), noMetadata(String)
    public var errorDescription: String? {
        switch self {
        case .unrecognized: return "Enter a DOI, URL, PMID, arXiv ID, or valid ISBN. For a quote, add its source below."
        case .noMetadata(let detail): return "No usable metadata was retrieved.\n" + detail
        case .multipleResults: return "The provider returned multiple sources. Use the URL of a single article or book."
        case .identifierMismatch: return "The provider returned a different identifier. The metadata was not accepted."
        case .disabled(let provider): return "\(provider) is disabled. Enable it in Preferences to look up this identifier."
        case .unavailable(let status): return "The metadata provider returned HTTP \(status). Try again or use the publisher URL."
        case .incomplete: return "Source recognized, but no usable title was found. Try its DOI or publisher page."
        case .tooLarge: return "This response is too large. Use a DOI or an article webpage instead."
        }
    }
}
public struct CitationResolver: Sendable {
    public var options: ResolverOptions
    public var client: HTTPClient
    public init(options: ResolverOptions = ResolverOptions(), client: HTTPClient = HTTPClient()) { self.options = options; self.client = client }
    public func resolve(_ input: String) async throws -> CitationItem {
        try Task.checkCancellation()
        var candidates: [MetadataCandidate] = []
        var checks: [ProviderCheck] = options.zoteroStartupIssue.map { [ProviderCheck("Zotero", .unavailable, $0)] } ?? []
        var webpageURL: URL?
        switch SourceClassifier.classify(input) {
        case .doi(let doi):
            webpageURL = URL(string: "https://doi.org/" + doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#")))!)
            do {
                let item = try await crossref(doi)
                candidates.append(MetadataCandidate(item, provider: "Crossref")); checks.append(ProviderCheck("Crossref", .matched, "DOI matched: " + doi))
            } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                try Task.checkCancellation(); checks.append(ProviderCheck("Crossref", .unavailable, error.localizedDescription))
            }
        case .pmid(let id):
            guard options.usePubMed else { throw ResolutionError.disabled("PubMed") }
            let data = try await client.get(URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=\(id)&retmode=xml&tool=CiteKit")!)
            let item = try ProviderDecoders.pubmed(data, expectedID: id)
            candidates.append(MetadataCandidate(item, provider: "PubMed")); checks.append(ProviderCheck("PubMed", .matched, "PMID matched: " + id))
            webpageURL = URL(string: item.url)
        case .arxiv(let id):
            guard options.useArxiv else { throw ResolutionError.disabled("arXiv") }
            try await ArxivRequestGate.shared.wait()
            var url = URLComponents(string: "https://export.arxiv.org/api/query")!; url.queryItems = [URLQueryItem(name: "id_list", value: id)]
            let item = try ProviderDecoders.arxiv(try await client.get(url.url!), expectedID: id)
            candidates.append(MetadataCandidate(item, provider: "arXiv")); checks.append(ProviderCheck("arXiv", .matched, "Preprint identifier matched: " + id))
            // Publisher versions are different works; do not merge journal metadata into a preprint.
        case .isbn(let id):
            guard options.useISBN else { throw ResolutionError.disabled("ISBN lookup") }
            let url = URL(string: "https://openlibrary.org/isbn/\(id).json")!
            let data = try await client.get(url)
            let edition = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let authorKeys = (edition["authors"] as? [[String: String]] ?? []).compactMap { $0["key"] }.filter { $0.range(of: "^/authors/OL[0-9]+A$", options: .regularExpression) != nil }
            var names: [String: String] = [:]
            for key in authorKeys.prefix(20) {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 350_000_000)
                do {
                    let authorData = try await client.get(URL(string: "https://openlibrary.org" + key + ".json")!)
                    let author = try JSONSerialization.jsonObject(with: authorData) as? [String: Any]
                    if author?["key"] as? String == key { names[key] = author?["name"] as? String }
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                    try Task.checkCancellation()
                }
            }
            let item = try ProviderDecoders.isbn(data, expectedISBN: id, authorNames: names)
            candidates.append(MetadataCandidate(item, provider: "Open Library")); checks.append(ProviderCheck("Open Library", .matched, "ISBN checksum and returned identifier matched: " + id))
            webpageURL = URL(string: item.url)
        case .url(let url): webpageURL = url
        case .text: throw ResolutionError.unrecognized
        }
        if let url = webpageURL {
            if candidates.isEmpty || options.compareWebMetadata {
                do {
                    let data = try await client.get(url)
                    guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ResolutionError.incomplete }
                    let item = try WebMetadata.extract(html, url: url)
                    candidates.append(MetadataCandidate(item, provider: "Webpage")); checks.append(ProviderCheck("Webpage", .extracted, "Publisher/page metadata extracted."))
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                    try Task.checkCancellation()
                    checks.append(ProviderCheck("Webpage", .unavailable, error.localizedDescription))
                }
            } else { checks.append(ProviderCheck("Webpage", .skipped, "Webpage comparison disabled in Preferences.")) }
            if let endpoint = options.zoteroEndpoint {
                do {
                    var request = URLRequest(url: endpoint.appendingPathComponent("web")); request.httpMethod = "POST"
                    if let token = options.zoteroAuthorizationToken { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
                    request.setValue("text/plain", forHTTPHeaderField: "Content-Type"); request.httpBody = Data(url.absoluteString.utf8)
                    let item = try ProviderDecoders.zotero(try await client.send(request), sourceURL: url)
                    candidates.append(MetadataCandidate(item, provider: "Zotero")); checks.append(ProviderCheck("Zotero", .extracted, "Translated a single source using the configured server."))
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                    try Task.checkCancellation()
                    checks.append(ProviderCheck("Zotero", .unavailable, error.localizedDescription))
                }
            } else if options.zoteroStartupIssue == nil { checks.append(ProviderCheck("Zotero", .skipped, "Zotero is disabled in Preferences.")) }
        }
        if !checks.contains(where: { $0.provider == "Crossref" }), let doi = candidates.compactMap({ $0.item.doi }).first {
            do {
                let item = try await crossref(doi)
                candidates.append(MetadataCandidate(item, provider: "Crossref")); checks.append(ProviderCheck("Crossref", .matched, "DOI matched: " + doi))
            } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                try Task.checkCancellation()
                checks.append(ProviderCheck("Crossref", .unavailable, error.localizedDescription))
            }
        }
        if candidates.isEmpty { throw ResolutionError.noMetadata(checks.map { "\($0.provider): \($0.detail)" }.joined(separator: "\n")) }
        try Task.checkCancellation()
        return try MetadataMerger.merge(candidates, checks: checks)
    }
    private func crossref(_ doi: String) async throws -> CitationItem {
        let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#")))!
        let data = try await client.get(URL(string: "https://api.crossref.org/works/" + encoded)!)
        let item = try Self.decodeCrossref(data)
        guard item.doi?.lowercased() == doi.lowercased() else { throw ResolutionError.identifierMismatch }
        return item
    }
    public static func decodeCrossref(_ data: Data) throws -> CitationItem {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let m = root["message"] as? [String: Any], let title = (m["title"] as? [String])?.first, !title.isEmpty else { throw ResolutionError.incomplete }
        let doi = m["DOI"] as? String
        var item = CitationItem(title: WebMetadata.clean(title), url: doi.map { "https://doi.org/" + $0 } ?? (m["URL"] as? String ?? ""))
        item.type = ["journal-article": "article-journal", "book": "book", "monograph": "book", "book-chapter": "chapter"][m["type"] as? String ?? ""] ?? "article"
        item.doi = doi
        item.authors = (m["author"] as? [[String: Any]] ?? []).map { Creator(given: $0["given"] as? String ?? "", family: $0["family"] as? String ?? "", literal: $0["name"] as? String) }.filter { !$0.display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        item.container = (m["container-title"] as? [String])?.first ?? ""
        item.publisher = m["publisher"] as? String ?? ""
        let date = m["published"] as? [String: Any] ?? m["published-print"] as? [String: Any] ?? m["published-online"] as? [String: Any]
        if let parts = (date?["date-parts"] as? [[Int]])?.first {
            item.year = parts.first; item.month = parts.count > 1 ? parts[1] : nil; item.day = parts.count > 2 ? parts[2] : nil
        }
        item.volume = m["volume"] as? String ?? ""; item.issue = m["issue"] as? String ?? ""; item.pages = m["page"] as? String ?? ""
        for field in ["title", "authors", "date", "container", "doi"] {
            let exists = field == "authors" ? !item.authors.isEmpty : field == "date" ? item.year != nil : field == "container" ? !item.container.isEmpty : field == "doi" ? item.doi != nil : true
            if exists { item.evidence[field] = FieldEvidence("Crossref", 0.95) }
        }
        return item
    }
}
public enum WebMetadata {
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    public static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: value) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func person(_ name: String) -> Creator {
        let comma = name.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if comma.count == 2 { return Creator(given: comma[1], family: comma[0]) }
        let parts = name.split(separator: " ")
        guard parts.count > 1 else { return Creator(family: name) }
        return Creator(given: parts.dropLast().joined(separator: " "), family: String(parts.last!))
    }
    public static func extract(_ html: String, url: URL) throws -> CitationItem {
        var tags: [String: [String]] = [:]
        for tag in matches("<meta\\b[^>]*>", html) {
            var attributes: [String: String] = [:]
            for a in matches("([\\w:-]+)\\s*=\\s*([\"'])(.*?)\\2", tag[0]) { attributes[a[1].lowercased()] = clean(a[3]) }
            if let name = attributes["name"] ?? attributes["property"], let value = attributes["content"] { tags[name.lowercased(), default: []].append(value) }
        }
        func meta(_ keys: String...) -> String? { keys.compactMap { tags[$0]?.first }.first { !$0.isEmpty } }
        var structured: [String: Any]?
        func visit(_ node: Any) {
            if let array = node as? [Any] { array.forEach(visit); return }
            guard let object = node as? [String: Any] else { return }
            let types = object["@type"] as? [String] ?? [object["@type"] as? String ?? ""]
            if structured == nil && types.contains(where: { ["ScholarlyArticle", "Article", "NewsArticle", "BlogPosting", "Book", "WebPage"].contains($0) }) { structured = object }
            if let graph = object["@graph"] { visit(graph) }
        }
        for script in matches("<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>", html) {
            if let data = script[1].data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) { visit(object) }
        }
        let structuredTitle = structured?["headline"] as? String ?? structured?["name"] as? String
        guard let title = structuredTitle ?? meta("citation_title", "og:title", "twitter:title") ?? matches("<title[^>]*>(.*?)</title>", html).first?[1], !clean(title).isEmpty else { throw ResolutionError.incomplete }
        var item = CitationItem(title: clean(title), url: url.absoluteString)
        item.evidence["title"] = FieldEvidence(structuredTitle != nil ? "JSON-LD" : "HTML metadata", 0.7)
        if let authors = structured?["author"] {
            let list = authors as? [Any] ?? [authors]
            item.authors = list.compactMap { value in
                if let string = value as? String { return person(string) }
                guard let object = value as? [String: Any], let name = object["name"] as? String else { return nil }
                return object["@type"] as? String == "Organization" ? Creator(literal: name) : person(name)
            }
        }
        if item.authors.isEmpty { item.authors = (tags["citation_author"] ?? tags["author"] ?? []).map { person($0) } }
        item.container = meta("citation_journal_title", "og:site_name") ?? ""
        item.type = tags["citation_journal_title"] == nil ? "webpage" : "article-journal"
        item.publisher = (structured?["publisher"] as? [String: Any])?["name"] as? String ?? ""
        let date = structured?["datePublished"] as? String ?? meta("citation_publication_date", "article:published_time", "date")
        if let date, let year = matches("^([0-9]{4})(?:[-/]([0-9]{1,2}))?(?:[-/]([0-9]{1,2}))?", date).first {
            item.year = Int(year[1]); item.month = Int(year[2]); item.day = Int(year[3])
        }
        if let raw = meta("citation_doi"), case .doi(let doi) = SourceClassifier.classify(raw) { item.doi = doi }
        item.volume = meta("citation_volume") ?? ""; item.issue = meta("citation_issue") ?? ""
        item.pages = [meta("citation_firstpage"), meta("citation_lastpage")].compactMap { $0 }.joined(separator: "–")
        if !item.authors.isEmpty { item.evidence["authors"] = FieldEvidence("Webpage metadata", 0.65) }
        if item.year != nil { item.evidence["date"] = FieldEvidence("Webpage metadata", 0.7) }
        if structuredTitle == nil && meta("citation_title", "og:title", "twitter:title") == nil { item.evidence["title"] = FieldEvidence("HTML title fallback", 0.4) }
        if !item.container.isEmpty { item.evidence["container"] = FieldEvidence("Webpage metadata", 0.7) }
        return item
    }
}

private actor ArxivRequestGate {
    static let shared = ArxivRequestGate()
    private var next = Date.distantPast
    func wait() async throws {
        let now = Date(); let reserved = max(now, next); next = reserved.addingTimeInterval(3)
        let delay = reserved.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}
