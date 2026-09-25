import Foundation

public struct Creator: Codable, Equatable, Sendable {
    public var given: String
    public var family: String
    public var literal: String?
    public init(given: String = "", family: String = "", literal: String? = nil) {
        self.given = given; self.family = family; self.literal = literal
    }
    public var display: String { literal ?? [given, family].filter { !$0.isEmpty }.joined(separator: " ") }
}
public struct FieldEvidence: Codable, Sendable {
    public var provider: String
    public var confidence: Double
    public init(_ provider: String, _ confidence: Double) { self.provider = provider; self.confidence = confidence }
}
public struct CitationItem: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var type = "webpage"
    public var authors: [Creator] = []
    public var container = ""
    public var publisher = ""
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var doi: String?
    public var pmid: String?
    public var arxivID: String?
    public var isbn: String?
    public var checks: [ProviderCheck]?
    public var conflicts: [MetadataConflict]?
    public var url: String
    public var volume = ""
    public var issue = ""
    public var pages = ""
    public var evidence: [String: FieldEvidence] = [:]
    public var warnings: [String] = []
    public var accessed = Date()
    public init(title: String, url: String) { self.title = title; self.url = url }
    public var identity: String {
        if let doi { return "doi:" + doi.lowercased() }
        if let pmid { return "pmid:" + pmid }
        if let arxivID { return "arxiv:" + arxivID.lowercased() }
        if let isbn { return "isbn:" + isbn }
        return "url:" + url
    }
    public var confidence: ConfidenceReport { ConfidenceEngine.evaluate(self) }
    public var health: String { confidence.level.rawValue }
    public var missingFields: [String] { confidence.issues }
    public var csl: [String: Any] {
        var result: [String: Any] = ["id": id.uuidString, "type": type, "title": title, "URL": url,
            "container-title": container, "publisher": publisher, "volume": volume, "issue": issue, "page": pages,
            "author": authors.map { a -> [String: String] in
                if let literal = a.literal { return ["literal": literal] }
                return ["given": a.given, "family": a.family]
            }]
        if let doi { result["DOI"] = doi }
        if let year { result["issued"] = ["date-parts": [[year] + (month.map { [$0] } ?? []) + (month != nil ? day.map { [$0] } ?? [] : [])]] }
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: accessed)
        result["accessed"] = ["date-parts": [[c.year!, c.month!, c.day!]]]
        return result
    }
}
