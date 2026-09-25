import Foundation

public struct ProviderCheck: Codable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case matched, extracted, unavailable, skipped }
    public var provider: String
    public var status: Status
    public var detail: String
    public var id: String { provider + detail }
    public init(_ provider: String, _ status: Status, _ detail: String) { self.provider = provider; self.status = status; self.detail = detail }
}
public struct MetadataAlternative: Codable, Sendable, Identifiable {
    public var provider: String
    public var value: String
    public var id: String { provider + value }
    public var display: String {
        if let data = value.data(using: .utf8), let authors = try? JSONDecoder().decode([Creator].self, from: data) { return authors.map(\.display).joined(separator: ", ") }
        return value
    }
}
public struct MetadataConflict: Codable, Sendable, Identifiable {
    public var field: String
    public var alternatives: [MetadataAlternative]
    public var selectedProvider: String
    public var reviewed = false
    public var id: String { field }
}
public enum ConfidenceLevel: String, Codable, Sendable { case verified = "Verified", high = "High confidence", medium = "Medium confidence", low = "Low confidence" }
public struct ConfidenceReport: Sendable {
    public var level: ConfidenceLevel
    public var summary: String
    public var issues: [String]
}
public enum ConfidenceEngine {
    public static func evaluate(_ item: CitationItem) -> ConfidenceReport {
        let checks = item.checks ?? []
        let matched = checks.filter { $0.status == .matched }.map(\.provider)
        // Older saved records keep their original Crossref evidence.
        let doiVerified = item.doi != nil && (matched.contains("Crossref") || (item.checks == nil && item.evidence["doi"]?.provider == "Crossref"))
        let zotero = checks.contains { $0.provider == "Zotero" && $0.status == .extracted }
        let trusted = doiVerified || matched.contains("PubMed") || matched.contains("arXiv") || matched.contains("Open Library")
        var issues = item.warnings
        var critical = 0
        if item.title.isEmpty { issues.append("Title unavailable."); critical += 1 }
        if item.authors.isEmpty { issues.append("Author unavailable; author-based citations may be incomplete."); critical += 1 }
        if item.year == nil { issues.append("Publication date unavailable; citations will use no-date conventions."); critical += 1 }
        if let year = item.year, year <= 0 || year > Calendar.current.component(.year, from: Date()) + 1 { issues.append("Publication year is outside the expected range. Check the original source."); critical += 1 }
        if let month = item.month, !(1...12).contains(month) { issues.append("Publication month is invalid."); critical += 1 }
        if let day = item.day, !(1...31).contains(day) { issues.append("Publication day is invalid."); critical += 1 }
        if item.type == "article-journal" && item.container.isEmpty { issues.append("Journal title unavailable."); critical += 1 }
        if item.type == "book" && item.publisher.isEmpty { issues.append("Book publisher unavailable."); critical += 1 }
        if item.type == "webpage" && item.container.isEmpty { issues.append("Website title unavailable.") }
        if item.type == "article-journal" && item.pages.isEmpty { issues.append("Article page range unavailable. Enter a locator when quoting.") }
        if item.doi == nil { issues.append("No DOI detected. This does not by itself make a source unreliable.") }
        else if !doiVerified { issues.append("DOI is present but was not verified against Crossref.") }
        if !doiVerified && !zotero { issues.append("No Crossref DOI verification or Zotero extraction was obtained.") }
        if !trusted && !zotero { issues.append("Webpage metadata has not been independently verified.") }
        if zotero { issues.append("Zotero extracted webpage metadata; this is not independent confirmation of the publisher’s claims.") }
        for check in checks where check.status == .unavailable { issues.append("\(check.provider) verification unavailable: \(check.detail)") }
        let conflicts = item.conflicts ?? []
        for conflict in conflicts {
            issues.append("\(conflict.field.capitalized) differs between providers. \(conflict.reviewed ? "You selected" : "Currently using") \(conflict.selectedProvider).")
        }
        if item.arxivID != nil { issues.append("arXiv is a preprint repository; an identifier match does not establish peer review.") }
        let level: ConfidenceLevel
        let failed = checks.contains { $0.status == .unavailable }
        if critical >= 2 || item.title.isEmpty { level = .low }
        else if !conflicts.isEmpty || critical > 0 { level = trusted || zotero ? .medium : .low }
        else if doiVerified && !failed { level = .verified }
        else if trusted || zotero { level = .high }
        else if item.evidence["title"]?.confidence ?? 0 >= 0.65 { level = .medium }
        else { level = .low }
        let summary: String
        switch level {
        case .verified: summary = "DOI matched Crossref; essential metadata is present and no checked fields conflict."
        case .high: summary = "Structured metadata is available. Review the limitations and provider checks below."
        case .medium: summary = "Review this citation: metadata is unverified, incomplete, or differs between providers."
        case .low: summary = "Important metadata is missing or relies on weak extraction. Check the source before using this citation."
        }
        var seen = Set<String>()
        return ConfidenceReport(level: level, summary: summary, issues: issues.filter { seen.insert($0).inserted })
    }
}
public struct MetadataCandidate: Sendable {
    public var item: CitationItem
    public var provider: String
    public init(_ item: CitationItem, provider: String) { self.item = item; self.provider = provider }
}
public enum MetadataMerger {
    static let fields = ["title", "authors", "date", "container", "publisher", "volume", "issue", "pages", "doi"]
    static func values(_ item: CitationItem) -> [String: String] {
        var result = ["title": item.title, "container": item.container, "publisher": item.publisher, "volume": item.volume, "issue": item.issue, "pages": item.pages, "doi": item.doi ?? ""]
        if !item.authors.isEmpty, let data = try? JSONEncoder().encode(item.authors) { result["authors"] = String(data: data, encoding: .utf8) }
        if let year = item.year { result["date"] = String(year) + (item.month.map { String(format: "-%02d", $0) } ?? "") + (item.month != nil ? item.day.map { String(format: "-%02d", $0) } ?? "" : "") }
        return result.filter { !$0.value.isEmpty }
    }
    static func rank(_ provider: String, field: String) -> Int {
        switch provider {
        case "Crossref": return field == "date" ? 90 : 100
        case "PubMed": return field == "authors" || field == "date" ? 98 : 95
        case "arXiv": return 92
        case "Open Library": return 90
        case "Zotero": return 85
        case "Webpage": return field == "date" ? 80 : 65
        default: return 40
        }
    }
    static func normalized(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")).replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression) }
    static func agree(_ a: String, _ b: String, field: String) -> Bool {
        if field == "date" { return a == b || a.hasPrefix(b + "-") || b.hasPrefix(a + "-") }
        if field == "authors", let ad = a.data(using: .utf8), let bd = b.data(using: .utf8), let aa = try? JSONDecoder().decode([Creator].self, from: ad), let bb = try? JSONDecoder().decode([Creator].self, from: bd), aa.count == bb.count {
            return zip(aa, bb).allSatisfy { x, y in
                if x.literal != nil || y.literal != nil { return normalized(x.display) == normalized(y.display) }
                let gx = normalized(x.given), gy = normalized(y.given)
                let tx = x.given.split(separator: " ").map { normalized(String($0)) }, ty = y.given.split(separator: " ").map { normalized(String($0)) }
                let compatible = !tx.isEmpty && !ty.isEmpty && zip(tx, ty).allSatisfy { a, b in a == b || (a.count == 1 && b.hasPrefix(a)) || (b.count == 1 && a.hasPrefix(b)) }
                return normalized(x.family) == normalized(y.family) && (gx == gy || compatible)
            }
        }
        return normalized(a) == normalized(b)
    }
    public static func merge(_ candidates: [MetadataCandidate], checks: [ProviderCheck]) throws -> CitationItem {
        guard var item = candidates.max(by: { rank($0.provider, field: "title") < rank($1.provider, field: "title") })?.item else { throw ResolutionError.incomplete }
        item.checks = checks; item.conflicts = []; item.warnings = candidates.flatMap { $0.item.warnings }; item.evidence = [:]
        for candidate in candidates {
            item.pmid = item.pmid ?? candidate.item.pmid; item.arxivID = item.arxivID ?? candidate.item.arxivID; item.isbn = item.isbn ?? candidate.item.isbn
        }
        for field in fields {
            let options = candidates.compactMap { candidate -> MetadataAlternative? in
                guard let value = values(candidate.item)[field] else { return nil }
                return MetadataAlternative(provider: candidate.provider, value: value)
            }.sorted { rank($0.provider, field: field) > rank($1.provider, field: field) }
            guard var best = options.first else { continue }
            // Keep the fuller compatible author/date value without inventing missing information.
            for option in options.dropFirst() where ["authors", "date"].contains(field) && agree(best.value, option.value, field: field) && option.value.count > best.value.count { best = option }
            apply(field, value: best.value, to: &item)
            let candidateEvidence = candidates.first { $0.provider == best.provider }?.item.evidence[field]
            item.evidence[field] = candidateEvidence ?? FieldEvidence(best.provider, Double(rank(best.provider, field: field)) / 100)
            item.evidence[field]?.provider = best.provider
            if options.contains(where: { !agree(best.value, $0.value, field: field) }) {
                item.conflicts?.append(MetadataConflict(field: field, alternatives: options, selectedProvider: best.provider))
            }
        }
        return item
    }
    public static func select(field: String, provider: String, in item: inout CitationItem) {
        guard let index = item.conflicts?.firstIndex(where: { $0.field == field }), let option = item.conflicts?[index].alternatives.first(where: { $0.provider == provider }) else { return }
        apply(field, value: option.value, to: &item)
        item.conflicts?[index].selectedProvider = provider; item.conflicts?[index].reviewed = true
        item.evidence[field] = FieldEvidence("Manual choice: " + provider, 0.7)
    }
    static func apply(_ field: String, value: String, to item: inout CitationItem) {
        switch field {
        case "title": item.title = value
        case "authors": if let data = value.data(using: .utf8), let authors = try? JSONDecoder().decode([Creator].self, from: data) { item.authors = authors }
        case "date": let p = value.split(separator: "-").compactMap { Int($0) }; item.year = p.first; item.month = p.count > 1 ? p[1] : nil; item.day = p.count > 2 ? p[2] : nil
        case "container": item.container = value
        case "publisher": item.publisher = value
        case "volume": item.volume = value
        case "issue": item.issue = value
        case "pages": item.pages = value
        case "doi": item.doi = value
        default: break
        }
    }
}
