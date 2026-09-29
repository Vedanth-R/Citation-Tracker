import Foundation
import Testing
@testable import CiteKitApp

@MainActor struct DashboardTests {
    @Test func activityPersistsAcrossInstancesAndSeparatesEvents() throws {
        let name = "CiteKitDashboardTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let stats = ActivityStats(defaults: defaults)
        #expect(stats.snapshot.generated == 0)
        let since = stats.snapshot.since
        stats.record(.generated)
        stats.record(.generated)
        stats.record(.copied)
        stats.record(.search)
        let reopened = ActivityStats(defaults: defaults)
        #expect(reopened.snapshot.generated == 2)
        #expect(reopened.snapshot.copied == 1)
        #expect(reopened.snapshot.searches == 1)
        #expect(reopened.snapshot.since == since)
        #expect(reopened.week.count == 7)
        #expect(reopened.week.last?.count == 2)
        #expect(reopened.week.dropLast().allSatisfy { $0.count == 0 })
    }
}
