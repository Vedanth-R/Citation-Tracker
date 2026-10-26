import Foundation

/// Search candidates are suggestions, never verified citations. Resolve the selected DOI normally.
public struct SourceSearchResult: Identifiable, Sendable {
    public var id: String { doi.lowercased() }
    public let doi: String
    public let title: String
    public let authors: String
    public let publication: String
    public let year: Int?
    public var url: URL { URL(string: "https://doi.org/" + doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#")))!)! }
}
public enum SourceSearchError: LocalizedError {
    case empty, tooLong, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .empty: return "Enter a title, author, publication, date, or combination to search."
        case .tooLong: return "Select a shorter reference (up to 1,000 characters)."
        case .invalidResponse: return "The search provider returned an unreadable response. Try again."
        }
    }
}
public struct SourceSearch: Sendable {
    public var client: HTTPClient
    public init(client: HTTPClient = HTTPClient()) { self.client = client }
    public func search(_ text: String) async throws -> [SourceSearchResult] {
        let query = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !query.isEmpty else { throw SourceSearchError.empty }
        guard query.count <= 1_000 else { throw SourceSearchError.tooLong }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://api.crossref.org/works")!
        url.queryItems = [URLQueryItem(name: "query.bibliographic", value: query), URLQueryItem(name: "rows", value: "10")]
        let data = try await client.get(url.url!)
        try Task.checkCancellation()
        return try Self.decode(data)
    }
    static func decode(_ data: Data) throws -> [SourceSearchResult] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any], let records = message["items"] as? [[String: Any]] else { throw SourceSearchError.invalidResponse }
        var seen = Set<String>()
        return records.compactMap { record in
            guard let doi = record["DOI"] as? String,
                  case .doi = SourceClassifier.classify(doi),
                  let wrapped = try? JSONSerialization.data(withJSONObject: ["message": record]),
                  let item = try? CitationResolver.decodeCrossref(wrapped), !item.title.isEmpty,
                  seen.insert(doi.lowercased()).inserted else { return nil }
            return SourceSearchResult(doi: doi, title: item.title, authors: item.authors.map(\.display).joined(separator: ", "), publication: item.container, year: item.year)
        }
    }
}
