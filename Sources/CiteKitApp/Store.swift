import SwiftUI
import CoreData
import Combine
import CiteKitCore

final class CitationRecord: Identifiable, Codable {
    var identity: String
    var payload: Data
    var lastUsed: Date
    var quotes: [QuoteRecord] = []
    var id: String { identity }
    init(_ item: CitationItem) throws {
        identity = item.identity; payload = try JSONEncoder().encode(item); lastUsed = Date()
    }
    var item: CitationItem? { try? JSONDecoder().decode(CitationItem.self, from: payload) }
}
final class QuoteRecord: Identifiable, Codable {
    var id = UUID()
    var text: String
    var page: String
    var createdAt: Date
    var application: String
    init(text: String, page: String, application: String) { self.text = text; self.page = page; self.application = application; createdAt = Date() }
}
@MainActor final class CitationRepository: ObservableObject {
    @Published var records: [CitationRecord] = []
    private let context: NSManagedObjectContext
    init(inMemory: Bool = false) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription(); entity.name = "SavedSource"; entity.managedObjectClassName = "NSManagedObject"
        let identity = NSAttributeDescription(); identity.name = "identity"; identity.attributeType = .stringAttributeType
        let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType
        entity.properties = [identity, payload]; entity.uniquenessConstraints = [["identity"]]; model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let directory = inMemory ? FileManager.default.temporaryDirectory : try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CiteKit", isDirectory: true)
        if !inMemory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType, configurationName: nil, at: inMemory ? nil : directory.appendingPathComponent("History.sqlite"))
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType); context.persistentStoreCoordinator = coordinator
        let objects = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "SavedSource"))
        records = try objects.map { object in
            guard let data = object.value(forKey: "payload") as? Data else { throw CocoaError(.coderReadCorrupt) }
            return try JSONDecoder().decode(CitationRecord.self, from: data)
        }.sorted { $0.lastUsed > $1.lastUsed }
    }
    func save(_ record: CitationRecord) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SavedSource"); request.predicate = NSPredicate(format: "identity == %@", record.identity)
        let object = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "SavedSource", into: context)
        object.setValue(record.identity, forKey: "identity"); object.setValue(try JSONEncoder().encode(record), forKey: "payload")
        do { try context.save() } catch { context.rollback(); throw error }
        records.removeAll { $0.identity == record.identity }; records.insert(record, at: 0)
    }
    func delete(_ record: CitationRecord) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SavedSource"); request.predicate = NSPredicate(format: "identity == %@", record.identity)
        for object in try context.fetch(request) { context.delete(object) }
        do { try context.save() } catch { context.rollback(); throw error }
        records.removeAll { $0.identity == record.identity }
    }
}
@MainActor final class AppState: ObservableObject {
    @Published var input = ""
    @Published var quote = ""
    @Published var page = ""
    @Published var item: CitationItem?
    @Published var output: FormattedCitation?
    @Published var busy = false
    @Published var error: String?
    @Published var notice = ""
    @Published var style: CitationStyle = .mla { didSet { refresh() } }
    var repository: CitationRepository?
    var sourceApplication = ""
    private var preferenceSubscription: AnyCancellable?
    init() {
        style = Preferences.shared.style
        preferenceSubscription = Preferences.shared.$style.dropFirst().sink { [weak self] style in self?.style = style }
    }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func resetCapture() {
        task?.cancel(); generation = UUID(); busy = false; item = nil; output = nil; error = nil; notice = ""
    }
    func generate() {
        task?.cancel()
        let token = UUID(); generation = token
        let source = input
        busy = true; error = nil; notice = ""; item = nil; output = nil
        task = Task {
            do {
                let options = await Preferences.shared.preparedResolverOptions()
                try Task.checkCancellation()
                let result = try await CitationResolver(options: options).resolve(source)
                guard !Task.isCancelled, generation == token else { return }
                item = result; refresh(); try save()
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                self.error = error.localizedDescription
            }
            if generation == token { busy = false }
        }
    }
    func refresh() {
        guard let item else { return }
        do { output = try CitationFormatter().format(item, style: style, page: page); error = nil }
        catch { output = nil; self.error = error.localizedDescription }
    }
    @discardableResult func save() throws -> CitationRecord? {
        guard let repository, let item else { return nil }
        let key = item.identity
        let record: CitationRecord
        if let existing = repository.records.first(where: { record in record.identity == key || record.item.map { prior in (item.doi != nil && prior.doi?.lowercased() == item.doi?.lowercased()) || (item.pmid != nil && prior.pmid == item.pmid) || (item.arxivID != nil && prior.arxivID == item.arxivID) || (item.isbn != nil && prior.isbn == item.isbn) } == true }) {
            record = existing
            var updated = item
            if let prior = existing.item { updated.id = prior.id }
            record.payload = try JSONEncoder().encode(updated)
            record.lastUsed = Date()
        } else { record = try CitationRecord(item);  }
        try repository.save(record)
        return record
    }
    func saveQuote() {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if let record = try save() {
                if !record.quotes.contains(where: { $0.text == quote && $0.page == page }) { record.quotes.append(QuoteRecord(text: quote, page: page, application: sourceApplication)) }
                try repository?.save(record); notice = "Quote saved"
            }
        } catch { self.error = error.localizedDescription }
    }
    func chooseConflict(field: String, provider: String) {
        guard var updated = item else { return }
        // Identifiers remain the original identity; changing a DOI should start a fresh lookup.
        MetadataMerger.select(field: field, provider: provider, in: &updated)
        item = updated; refresh()
        do { try save(); notice = "Metadata choice saved; the original discrepancy remains visible." }
        catch { self.error = error.localizedDescription }
    }
    func copy(_ string: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(string, forType: .string); notice = "Copied" }
    func load(_ record: CitationRecord) { task?.cancel(); generation = UUID(); busy = false; item = record.item; input = item?.doi ?? item?.url ?? ""; quote = ""; page = ""; notice = ""; refresh() }
}
