import Foundation

public enum SourceInput: Equatable, Sendable {
    case doi(String), pmid(String), arxiv(String), isbn(String), url(URL), text(String)
}
public enum ISBNParser {
    public static func canonical13(_ text: String) -> String? {
        guard let isbn = normalize(text) else { return nil }
        if isbn.count == 13 { return isbn }
        let prefix = "978" + isbn.prefix(9)
        let total = prefix.enumerated().reduce(0) { $0 + $1.element.wholeNumberValue! * ($1.offset % 2 == 0 ? 1 : 3) }
        return prefix + String((10 - total % 10) % 10)
    }
    public static func normalize(_ text: String) -> String? {
        let value = text.replacingOccurrences(of: "(?i)^ISBN(?:-1[03])?:?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[-\\s]", with: "", options: .regularExpression).uppercased()
        let chars = Array(value)
        if chars.count == 10 {
            guard chars.prefix(9).allSatisfy({ $0.isASCII && $0.isNumber }), chars[9].isASCII && (chars[9].isNumber || chars[9] == "X") else { return nil }
            let sum = chars.enumerated().reduce(0) { $0 + (10 - $1.offset) * ($1.element == "X" ? 10 : $1.element.wholeNumberValue!) }
            return sum % 11 == 0 ? value : nil
        }
        if chars.count == 13, value.hasPrefix("978") || value.hasPrefix("979"), chars.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let sum = chars.enumerated().reduce(0) { $0 + $1.element.wholeNumberValue! * ($1.offset % 2 == 0 ? 1 : 3) }
            return sum % 10 == 0 ? value : nil
        }
        return nil
    }
}
public enum SourceClassifier {
    public static func classify(_ input: String) -> SourceInput {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for (left, right) in [("<", ">"), ("\"", "\""), ("“", "”"), ("(", ")")] {
            if text.hasPrefix(left), text.hasSuffix(right), text.count > 2 { text = String(text.dropFirst().dropLast()) }
        }
        func matches(_ pattern: String, _ value: String) -> Bool { value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        let doi = text.replacingOccurrences(of: "(?i)^doi:\\s*", with: "", options: .regularExpression)
        if matches("^10\\.[0-9]{4,9}/\\S+$", doi) { return .doi(doi) }
        if matches("^PMID:\\s*[0-9]{1,9}$", text) { return .pmid(text.components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)) }
        let arxiv = text.replacingOccurrences(of: "(?i)^arxiv:\\s*", with: "", options: .regularExpression)
        let arxivPattern = "^(?:[0-9]{4}\\.[0-9]{4,5}|[a-z-]+(?:\\.[A-Z]{2})?/[0-9]{7})(?:v[0-9]+)?$"
        if matches(arxivPattern, arxiv) { return .arxiv(arxiv) }
        if let isbn = ISBNParser.normalize(text) { return .isbn(isbn) }
        if text.lowercased().hasPrefix("www.") { text = "https://" + text }
        if var c = URLComponents(string: text), ["http", "https"].contains(c.scheme?.lowercased() ?? ""), let host = c.host?.lowercased(), !host.isEmpty, !text.contains(where: { $0.isWhitespace }), c.user == nil, c.password == nil {
            let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if ["doi.org", "dx.doi.org"].contains(host), matches("^10\\.[0-9]{4,9}/\\S+$", path) { return .doi(path) }
            if host == "pubmed.ncbi.nlm.nih.gov", matches("^[0-9]{1,9}$", path) { return .pmid(path) }
            if host == "www.ncbi.nlm.nih.gov", path.hasPrefix("pubmed/"), matches("^[0-9]{1,9}$", String(path.dropFirst(7))) { return .pmid(String(path.dropFirst(7))) }
            if ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(host), path.hasPrefix("abs/") || path.hasPrefix("pdf/") {
                let identifier = String(path.dropFirst(4)).replacingOccurrences(of: "\\.pdf$", with: "", options: .regularExpression)
                if matches(arxivPattern, identifier) { return .arxiv(identifier) }
            }
            c.fragment = nil
            c.queryItems = c.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
            if c.queryItems?.isEmpty == true { c.queryItems = nil }
            if let url = c.url { return .url(url) }
        }
        return .text(text)
    }
}
