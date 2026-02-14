import Testing
@testable import Infrastructure

@Suite("KiroUsageProbe Integration Tests")
struct KiroUsageProbeIntegrationTests {
    @Test
    func `execute kiro-cli and parse usage`() async throws {
        let probe = KiroUsageProbe()
        
        try #require(await probe.isAvailable(), "kiro-cli not available")
        
        let snapshot = try await probe.probe()
        
        #expect(snapshot.providerId == "kiro")
        #expect(!snapshot.quotas.isEmpty, "Should have at least one quota")
        
        print("✅ Quotas found: \(snapshot.quotas.count)")
        for quota in snapshot.quotas {
            print("  - \(quota.quotaType.displayName): \(quota.percentRemaining)%")
        }
    }
}
