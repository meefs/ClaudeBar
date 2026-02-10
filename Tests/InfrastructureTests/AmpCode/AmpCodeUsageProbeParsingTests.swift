import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct AmpCodeUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleOutput = """
    Signed in as user@example.com (username)
    Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """


    static let sampleOutputZeroRemaining = """
    Signed in as user@example.com (username)
    Amp Free: $0/$20 remaining (replenishes +$0.83/hour) - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """

    // MARK: - Parsing Tests

    @Test
    func `parses free tier credits into percentage`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - $17.59/$20 = 87.95%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Amp Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.percentRemaining == 87.95)
    }

    @Test
    func `extracts account email`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `handles zero remaining with total`() throws {
        // Given
        let text = Self.sampleOutputZeroRemaining

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - $0/$20 = 0%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Amp Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.percentRemaining == 0.0)
    }

    @Test
    func `skips lines without total`() throws {
        // Given - "Individual credits: $0 remaining" has no denominator
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - only "Amp Free" should produce a quota (it has $remaining/$total)
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("Amp Free"))
    }
    @Test
    func `maps to correct QuotaType`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        if case .modelSpecific(let name) = snapshot.quotas[0].quotaType {
            #expect(name == "Amp Free")
        } else {
            Issue.record("Expected modelSpecific quota type")
        }
    }

    @Test
    func `sets providerId correctly`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.providerId == "ampcode")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "ampcode" })
    }

    @Test
    func `extracts tier from free quota label`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.accountTier == .custom("Free"))
    }

    @Test
    func `returns nil tier for unsupported label`() throws {
        // Given
        let text = """
        Signed in as user@example.com (username)
        Amp Pro: $17.59/$20 remaining (replenishes +$0.83/hour)
        """

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.accountTier == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `throws parseFailed on empty output`() throws {
        // Given
        let text = ""

        // When/Then
        #expect(throws: ProbeError.self) {
            try AmpCodeUsageProbe.parse(text)
        }
    }

    @Test
    func `throws parseFailed on garbage output`() throws {
        // Given
        let text = "some random text that is not amp usage output"

        // When/Then
        #expect(throws: ProbeError.self) {
            try AmpCodeUsageProbe.parse(text)
        }
    }
}
