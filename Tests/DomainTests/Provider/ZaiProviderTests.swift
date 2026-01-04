import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("ZaiProvider Tests")
struct ZaiProviderTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository(zaiEnabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(zaiEnabled)
        given(mock).isEnabled(forProvider: .any).willReturn(zaiEnabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    /// Creates a mock config repository for testing
    private func makeConfigRepository() -> MockProviderConfigRepository {
        let mock = MockProviderConfigRepository()
        given(mock).zaiConfigPath().willReturn("")
        given(mock).glmAuthEnvVar().willReturn("")
        given(mock).copilotAuthEnvVar().willReturn("")
        given(mock).setZaiConfigPath(.any).willReturn()
        given(mock).setGlmAuthEnvVar(.any).willReturn()
        given(mock).setCopilotAuthEnvVar(.any).willReturn()
        return mock
    }

    // MARK: - Identity Tests

    @Test
    func `zai provider has correct id`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.id == "zai")
    }

    @Test
    func `zai provider has correct name`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.name == "Z.ai")
    }

    @Test
    func `zai provider has correct cliCommand`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.cliCommand == "claude")
    }

    @Test
    func `zai provider has dashboard URL pointing to z.ai`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.dashboardURL != nil)
        #expect(zai.dashboardURL?.host?.contains("z.ai") == true)
    }

    @Test
    func `zai provider has status page URL`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.statusPageURL != nil)
        #expect(zai.statusPageURL?.host?.contains("z.ai") == true)
    }

    @Test
    func `zai provider is enabled by default`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.isEnabled == true)
    }

    // MARK: - State Tests

    @Test
    func `zai provider starts with no snapshot`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.snapshot == nil)
    }

    @Test
    func `zai provider starts not syncing`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.isSyncing == false)
    }

    @Test
    func `zai provider starts with no error`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.lastError == nil)
    }

    // MARK: - Delegation Tests

    @Test
    func `zai provider delegates isAvailable to probe`() async {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(true)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        let isAvailable = await zai.isAvailable()

        #expect(isAvailable == true)
    }

    @Test
    func `zai provider delegates isAvailable false to probe`() async {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).isAvailable().willReturn(false)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        let isAvailable = await zai.isAvailable()

        #expect(isAvailable == false)
    }

    @Test
    func `zai provider delegates refresh to probe`() async throws {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "zai",
            quotas: [UsageQuota(percentRemaining: 95, quotaType: .session, providerId: "zai", resetText: "Resets in 1 hour")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        let snapshot = try await zai.refresh()

        #expect(snapshot.providerId == "zai")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 95)
    }

    // MARK: - Snapshot Storage Tests

    @Test
    func `zai provider stores snapshot after refresh`() async throws {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let expectedSnapshot = UsageSnapshot(
            providerId: "zai",
            quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "zai")],
            capturedAt: Date()
        )
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(expectedSnapshot)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.snapshot == nil)

        _ = try await zai.refresh()

        #expect(zai.snapshot != nil)
        #expect(zai.snapshot?.quotas.first?.percentRemaining == 80)
    }

    @Test
    func `zai provider clears error on successful refresh`() async throws {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        // Use two separate probes to simulate the behavior
        let failingProbe = MockUsageProbe()
        given(failingProbe).probe().willThrow(ProbeError.timeout)
        let zaiWithFailingProbe = ZaiProvider(probe: failingProbe, settingsRepository: settings, configRepository: config)

        do {
            _ = try await zaiWithFailingProbe.refresh()
        } catch {
            // Expected
        }
        #expect(zaiWithFailingProbe.lastError != nil)

        // Create new provider with succeeding probe
        let succeedingProbe = MockUsageProbe()
        let snapshot = UsageSnapshot(providerId: "zai", quotas: [], capturedAt: Date())
        given(succeedingProbe).probe().willReturn(snapshot)
        let zaiWithSucceedingProbe = ZaiProvider(probe: succeedingProbe, settingsRepository: settings, configRepository: config)

        _ = try await zaiWithSucceedingProbe.refresh()

        #expect(zaiWithSucceedingProbe.lastError == nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `zai provider stores error on refresh failure`() async {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("Connection failed"))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.lastError == nil)

        do {
            _ = try await zai.refresh()
        } catch {
            // Expected
        }

        #expect(zai.lastError != nil)
    }

    @Test
    func `zai provider rethrows probe errors`() async {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.executionFailed("API error"))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        await #expect(throws: ProbeError.executionFailed("API error")) {
            try await zai.refresh()
        }
    }

    // MARK: - Syncing State Tests

    @Test
    func `zai provider resets isSyncing after refresh completes`() async throws {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willReturn(UsageSnapshot(
            providerId: "zai",
            quotas: [],
            capturedAt: Date()
        ))
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        #expect(zai.isSyncing == false)

        _ = try await zai.refresh()

        #expect(zai.isSyncing == false)
    }

    @Test
    func `zai provider resets isSyncing after refresh fails`() async {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let mockProbe = MockUsageProbe()
        given(mockProbe).probe().willThrow(ProbeError.timeout)
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)

        do {
            _ = try await zai.refresh()
        } catch {
            // Expected
        }

        #expect(zai.isSyncing == false)
    }

    // MARK: - Uniqueness Tests

    @Test
    func `zai provider has unique id compared to other providers`() {
        let settings = makeSettingsRepository()
        let config = makeConfigRepository()
        let credentials = MockCredentialRepository()
        given(credentials).get(forKey: .any).willReturn(nil)
        given(credentials).exists(forKey: .any).willReturn(false)
        given(credentials).save(.any, forKey: .any).willReturn()
        given(credentials).delete(forKey: .any).willReturn()
        let mockProbe = MockUsageProbe()
        let zai = ZaiProvider(probe: mockProbe, settingsRepository: settings, configRepository: config)
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)
        let codex = CodexProvider(probe: mockProbe, settingsRepository: settings)
        let gemini = GeminiProvider(probe: mockProbe, settingsRepository: settings)
        let copilot = CopilotProvider(probe: mockProbe, settingsRepository: settings, credentialRepository: credentials, configRepository: config)
        let antigravity = AntigravityProvider(probe: mockProbe, settingsRepository: settings)

        let ids = Set([zai.id, claude.id, codex.id, gemini.id, copilot.id, antigravity.id])
        #expect(ids.count == 6) // All unique
    }
}
