import XCTest
@testable import Infrastructure

final class KiroUsageProbeIntegrationTests: XCTestCase {
    func testKiroCLIExecution() async throws {
        let probe = KiroUsageProbe()
        
        guard await probe.isAvailable() else {
            throw XCTSkip("kiro-cli not available")
        }
        
        let snapshot = try await probe.probe()
        
        XCTAssertEqual(snapshot.providerId, "kiro")
        XCTAssertFalse(snapshot.quotas.isEmpty, "Should have at least one quota")
        
        print("✅ Quotas found: \(snapshot.quotas.count)")
        for quota in snapshot.quotas {
            print("  - \(quota.quotaType.displayName): \(quota.percentRemaining)%")
        }
    }
}
