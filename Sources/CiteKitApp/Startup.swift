import AppKit
import SwiftUI
import CiteKitCore
import OSLog

struct StartupCheck: Sendable {
    let name: String
    let available: Bool
}
struct StartupProbe: Sendable {
    struct Endpoint: Sendable {
        let name: String
        let url: URL
        let marker: String
    }
    // Fixed public probes never include history, clipboard contents, or selected text.
    static func endpoints(_ options: ResolverOptions) -> [Endpoint] {
        var values = [Endpoint(name: "Crossref", url: URL(string: "https://api.crossref.org/works?rows=0")!, marker: "\"message\"")]
        if options.usePubMed { values.append(Endpoint(name: "PubMed", url: URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/einfo.fcgi?db=pubmed")!, marker: "<eInfoResult>")) }
        if options.useArxiv { values.append(Endpoint(name: "arXiv", url: URL(string: "https://export.arxiv.org/api/query?id_list=1706.03762&max_results=1")!, marker: "<feed")) }
        if options.useISBN { values.append(Endpoint(name: "Open Library", url: URL(string: "https://openlibrary.org/isbn/9780306406157.json")!, marker: "\"title\"")) }
        return values
    }
    static func reachable(_ endpoint: Endpoint, data: Data, status: Int) -> Bool {
        (200..<300).contains(status) && String(data: data, encoding: .utf8)?.contains(endpoint.marker) == true
    }
    static func run(_ options: ResolverOptions) async -> [StartupCheck] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await withTaskGroup(of: StartupCheck.self) { group in
            for endpoint in endpoints(options) {
                group.addTask {
                    do {
                        var request = URLRequest(url: endpoint.url)
                        request.setValue("CiteKit startup availability check", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await session.data(for: request)
                        return StartupCheck(name: endpoint.name, available: reachable(endpoint, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0))
                    } catch { return StartupCheck(name: endpoint.name, available: false) }
                }
            }
            var checks: [StartupCheck] = []
            for await check in group { checks.append(check) }
            return checks
        }
    }
    static func formatting() -> StartupCheck {
        var sample = CitationItem(title: "Startup check", url: "https://example.org")
        sample.authors = [Creator(given: "Jane", family: "Smith")]; sample.year = 2025
        do {
            for style in CitationStyle.allCases { _ = try CitationFormatter().format(sample, style: style) }
            return StartupCheck(name: "Citation formatting", available: true)
        } catch { return StartupCheck(name: "Citation formatting", available: false) }
    }
}

@MainActor final class StartupController {
    private var window: NSPanel?
    private(set) var dismissed = false
    private(set) var checks: [StartupCheck] = []
    func show() {
        guard !dismissed else { return }
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.level = .floating
            panel.contentView = NSHostingView(rootView: StartupView(onContinue: { [weak self] in self?.dismiss() }))
            panel.center(); window = panel
        }
        window?.orderFrontRegardless()
    }
    func record(_ check: StartupCheck) {
        checks.append(check)
        Logger(subsystem: "dev.citekit.mac", category: "startup").info("\(check.name, privacy: .public): \(check.available ? "available" : "unavailable", privacy: .public)")
    }
    func dismiss() { dismissed = true; window?.orderOut(nil); window = nil }
}
struct StartupView: View {
    var onContinue: () -> Void
    var body: some View {
        VStack(spacing: 17) {
            Image(systemName: "text.quote").font(.system(size: 36, weight: .medium)).foregroundStyle(.teal)
                .frame(width: 72, height: 72).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            Text("CiteKit").font(.system(size: 28, weight: .semibold, design: .rounded))
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Getting your workspace ready…").font(.callout).foregroundStyle(.secondary) }
            Button("Continue in background", action: onContinue).buttonStyle(.link).font(.caption).padding(.top, 5)
        }.frame(width: 420, height: 300).background(SpotlightMaterial())
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.12)))
    }
}
