import Foundation
import JavaScriptCore

public enum CitationStyle: String, CaseIterable, Identifiable { case mla = "MLA 9", apa = "APA 7", bibtex = "BibTeX"; public var id: String { rawValue } }
public struct FormattedCitation { public let full: String; public let inText: String; public let narrative: String }
public enum FormattingError: LocalizedError { case failed(String); public var errorDescription: String? { if case .failed(let message) = self { return message }; return nil } }
public final class CitationFormatter {
    public init() {}
    public func format(_ item: CitationItem, style: CitationStyle, page: String = "") throws -> FormattedCitation {
        if style == .bibtex { return FormattedCitation(full: bibtex(item), inText: "", narrative: "") }
        guard let context = JSContext() else { throw FormattingError.failed("Could not start the citation processor.") }
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        func resource(_ name: String, _ ext: String) throws -> String {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw FormattingError.failed("Missing citation resource: \(name)") }
            return try String(contentsOf: url, encoding: .utf8)
        }
        context.evaluateScript(try resource("citeproc", "js"))
        context.setObject(try resource(style == .mla ? "mla" : "apa", "csl"), forKeyedSubscript: "styleXML" as NSString)
        context.setObject(try resource("locales-en-US", "xml"), forKeyedSubscript: "localeXML" as NSString)
        context.setObject(item.csl, forKeyedSubscript: "sourceItem" as NSString)
        context.setObject(page, forKeyedSubscript: "pageLocator" as NSString)
        let result = context.evaluateScript("""
        var sys = {retrieveLocale: function(){return localeXML;}, retrieveItem: function(){return sourceItem;}};
        var engine = new CSL.Engine(sys, styleXML, 'en-US');
        engine.setOutputFormat('text');
        engine.updateItems([sourceItem.id]);
        var cite = {id: sourceItem.id};
        if (pageLocator) {cite.locator = pageLocator; cite.label = 'page';}
        var inline = engine.makeCitationCluster([cite]);
        var full = engine.makeBibliography()[1].join('').trim();
        var authorOnly = {id: sourceItem.id, 'author-only': true};
        var suppressed = {id: sourceItem.id, 'suppress-author': true};
        if (pageLocator) {suppressed.locator = pageLocator; suppressed.label = 'page';}
        var narrative = engine.makeCitationCluster([authorOnly]) + ' ' + engine.makeCitationCluster([suppressed]);
        ({full: full, inText: inline, narrative: narrative});
        """)
        guard failure == nil, let values = result?.toDictionary(), let full = values["full"] as? String, !full.isEmpty else {
            throw FormattingError.failed(failure ?? "Citation formatting failed.")
        }
        return FormattedCitation(full: full, inText: values["inText"] as? String ?? "", narrative: values["narrative"] as? String ?? "")
    }
    public func bibtex(_ item: CitationItem) -> String {
        func escape(_ value: String) -> String {
            value.map { char in
                switch char { case "\\": return "\\textbackslash{}"; case "{", "}", "%", "&", "_", "#", "$": return "\\" + String(char); case "~": return "\\textasciitilde{}"; case "^": return "\\textasciicircum{}"; default: return String(char) }
            }.joined()
        }
        var fields = [("title", item.title), (item.type == "article-journal" ? "journal" : "howpublished", item.container), ("year", item.year.map(String.init) ?? ""), ("publisher", item.publisher), ("volume", item.volume), ("number", item.issue), ("pages", item.pages), ("doi", item.doi ?? ""), ("url", item.url), ("isbn", item.isbn ?? ""), ("eprint", item.arxivID ?? ""), ("archivePrefix", item.arxivID == nil ? "" : "arXiv")]
        fields.removeAll { $0.1.isEmpty }
        let authors = item.authors.map { author in
            author.literal.map { "{" + escape($0) + "}" } ?? [author.family, author.given].filter { !$0.isEmpty }.map(escape).joined(separator: ", ")
        }.joined(separator: " and ")
        let authorField = authors.isEmpty ? [] : ["  author = {" + authors + "}"]
        return "@\(item.type == "article-journal" ? "article" : item.type == "book" ? "book" : "misc"){cite\(item.id.uuidString.prefix(8)),\n" + (authorField + fields.map { "  \($0.0) = {\(escape($0.1))}" }).joined(separator: ",\n") + "\n}"
    }
}
