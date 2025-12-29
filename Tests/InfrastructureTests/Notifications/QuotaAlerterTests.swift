import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Tests for QuotaAlerter.
@Suite(.serialized)
struct QuotaAlerterTests {

    // MARK: - Should Alert Tests

    @Test
    func `shouldAlert returns true for warning status`() {
        let alerter = QuotaAlerter()

        #expect(alerter.shouldAlert(for: .warning) == true)
    }

    @Test
    func `shouldAlert returns true for critical status`() {
        let alerter = QuotaAlerter()

        #expect(alerter.shouldAlert(for: .critical) == true)
    }

    @Test
    func `shouldAlert returns true for depleted status`() {
        let alerter = QuotaAlerter()

        #expect(alerter.shouldAlert(for: .depleted) == true)
    }

    @Test
    func `shouldAlert returns false for healthy status`() {
        let alerter = QuotaAlerter()

        #expect(alerter.shouldAlert(for: .healthy) == false)
    }

    // MARK: - Provider Display Name Tests

    @Test
    func `providerDisplayName uses registry for registered provider`() {
        // Given - register providers using Mockable
        let mockProbe = MockUsageProbe()
        AIProviderRegistry.shared.register([
            ClaudeProvider(probe: mockProbe),
            CodexProvider(probe: mockProbe),
            GeminiProvider(probe: mockProbe)
        ])
        let alerter = QuotaAlerter()

        // Then - returns provider name from registry
        #expect(alerter.providerDisplayName(for: "claude") == "Claude")
        #expect(alerter.providerDisplayName(for: "codex") == "Codex")
        #expect(alerter.providerDisplayName(for: "gemini") == "Gemini")
    }

    @Test
    func `providerDisplayName capitalizes unknown provider id`() {
        // Given - unknown provider IDs (not in registry)
        let alerter = QuotaAlerter()

        // Then - capitalizes the ID
        #expect(alerter.providerDisplayName(for: "unknown") == "Unknown")
        #expect(alerter.providerDisplayName(for: "chatgpt") == "Chatgpt")
    }

    // MARK: - Alert Body Tests

    @Test
    func `alertBody for warning describes low quota`() {
        let alerter = QuotaAlerter()

        let body = alerter.alertBody(for: .warning, providerName: "Claude")

        #expect(body.contains("Claude"))
        #expect(body.contains("running low"))
    }

    @Test
    func `alertBody for critical describes critically low`() {
        let alerter = QuotaAlerter()

        let body = alerter.alertBody(for: .critical, providerName: "Codex")

        #expect(body.contains("Codex"))
        #expect(body.contains("critically low"))
    }

    @Test
    func `alertBody for depleted describes depletion`() {
        let alerter = QuotaAlerter()

        let body = alerter.alertBody(for: .depleted, providerName: "Gemini")

        #expect(body.contains("Gemini"))
        #expect(body.contains("depleted"))
    }

    @Test
    func `alertBody for healthy describes recovery`() {
        let alerter = QuotaAlerter()

        let body = alerter.alertBody(for: .healthy, providerName: "Claude")

        #expect(body.contains("Claude"))
        #expect(body.contains("recovered"))
    }

    // MARK: - Status Degradation Detection (Domain Logic)

    @Test
    func `status degradation from healthy to warning should trigger alert`() {
        #expect(QuotaStatus.warning > QuotaStatus.healthy)
    }

    @Test
    func `status degradation from warning to critical should trigger alert`() {
        #expect(QuotaStatus.critical > QuotaStatus.warning)
    }

    @Test
    func `status degradation to depleted should trigger alert`() {
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `status improvement should not trigger alert`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `same status should not trigger alert`() {
        #expect(QuotaStatus.healthy == QuotaStatus.healthy)
    }

    // MARK: - onStatusChanged Integration Tests

    @Test
    func `onStatusChanged sends alert when status degrades to warning`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When
        await alerter.onStatusChanged(providerId: "claude", oldStatus: .healthy, newStatus: .warning)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("running low") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `onStatusChanged sends alert when status degrades to critical`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When
        await alerter.onStatusChanged(providerId: "codex", oldStatus: .warning, newStatus: .critical)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("critically low") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `onStatusChanged sends alert when status degrades to depleted`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When
        await alerter.onStatusChanged(providerId: "gemini", oldStatus: .critical, newStatus: .depleted)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("depleted") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `onStatusChanged does not send alert when status improves`() async {
        // Given
        let mockSender = MockAlertSender()
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When - status improves from warning to healthy
        await alerter.onStatusChanged(providerId: "claude", oldStatus: .warning, newStatus: .healthy)

        // Then - no alert sent
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(0)
    }

    @Test
    func `onStatusChanged does not send alert when status stays the same`() async {
        // Given
        let mockSender = MockAlertSender()
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When - status stays the same
        await alerter.onStatusChanged(providerId: "claude", oldStatus: .warning, newStatus: .warning)

        // Then - no alert sent
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(0)
    }

    @Test
    func `onStatusChanged silently handles alert errors`() async {
        // Given - sender throws an error
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willThrow(NSError(domain: "test", code: 1))
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When & Then - should not throw
        await alerter.onStatusChanged(providerId: "claude", oldStatus: .healthy, newStatus: .warning)

        // Verify alert was attempted
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(1)
    }

    @Test
    func `requestPermission delegates to alert sender`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).requestPermission().willReturn(true)
        let alerter = QuotaAlerter(alertSender: mockSender)

        // When
        let result = await alerter.requestPermission()

        // Then
        #expect(result == true)
        verify(mockSender).requestPermission().called(1)
    }
}
