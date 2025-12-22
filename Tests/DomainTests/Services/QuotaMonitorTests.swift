import Testing
import Foundation
@testable import Domain
import Mockable

@Suite
struct QuotaMonitorTests {

    // MARK: - Single Provider Monitoring

    @Test
    func `monitor fetches usage from a single provider`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let expectedSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [
                UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude),
                UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude),
            ],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(expectedSnapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.count == 1)
        #expect(snapshots[.claude]?.quotas.count == 2)
        #expect(snapshots[.claude]?.quota(for: .session)?.percentRemaining == 65)
    }

    @Test
    func `monitor skips unavailable providers`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(false)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.isEmpty)
    }

    // MARK: - Single Provider Refresh

    @Test
    func `refresh single provider returns only that provider snapshot`() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe])

        // When - refresh only Claude
        let snapshot = try await monitor.refresh(provider: .claude)

        // Then - only Claude is loaded, Codex probe not called
        #expect(snapshot?.provider == .claude)
        #expect(snapshot?.quota(for: .session)?.percentRemaining == 70)

        let allSnapshots = await monitor.allSnapshots()
        #expect(allSnapshots.count == 1)
        #expect(allSnapshots[.codex] == nil)
    }

    @Test
    func `refreshOthers excludes the specified provider`() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()
        let geminiProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )
        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, provider: .codex)],
            capturedAt: Date()
        )
        let geminiSnapshot = UsageSnapshot(
            provider: .gemini,
            quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, provider: .gemini)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(codexSnapshot)

        given(geminiProbe).provider.willReturn(.gemini)
        given(geminiProbe).isAvailable().willReturn(true)
        given(geminiProbe).probe().willReturn(geminiSnapshot)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe, geminiProbe])

        // When - refresh all except Claude
        let others = try await monitor.refreshOthers(except: .claude)

        // Then - Codex and Gemini loaded, Claude excluded
        #expect(others.count == 2)
        #expect(others[.claude] == nil)
        #expect(others[.codex]?.quota(for: .session)?.percentRemaining == 50)
        #expect(others[.gemini]?.quota(for: .session)?.percentRemaining == 30)
    }

    // MARK: - Multiple Provider Monitoring

    @Test
    func `monitor fetches from multiple providers concurrently`() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )
        let codexSnapshot = UsageSnapshot(
            provider: .codex,
            quotas: [UsageQuota(percentRemaining: 40, quotaType: .session, provider: .codex)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(codexSnapshot)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.count == 2)
        #expect(snapshots[.claude]?.quota(for: .session)?.percentRemaining == 70)
        #expect(snapshots[.codex]?.quota(for: .session)?.percentRemaining == 40)
    }

    @Test
    func `one provider failure does not affect others`() async throws {
        // Given
        let claudeProbe = MockUsageProbePort()
        let codexProbe = MockUsageProbePort()

        let claudeSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(claudeProbe).provider.willReturn(.claude)
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(claudeSnapshot)

        given(codexProbe).provider.willReturn(.codex)
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willThrow(ProbeError.timeout)

        let monitor = QuotaMonitor(probes: [claudeProbe, codexProbe])

        // When
        let snapshots = try await monitor.refreshAll()

        // Then
        #expect(snapshots.count == 1)
        #expect(snapshots[.claude] != nil)
        #expect(snapshots[.codex] == nil)
    }

    // MARK: - Status Change Detection

    @Test
    func `monitor notifies observer when status changes`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let mockObserver = MockQuotaObserverPort()

        let healthySnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        let warningSnapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 30, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        var callCount = 0
        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willProduce {
            callCount += 1
            return callCount == 1 ? healthySnapshot : warningSnapshot
        }

        given(mockObserver).onSnapshotUpdated(.any).willReturn()
        given(mockObserver).onStatusChanged(provider: .any, oldStatus: .any, newStatus: .any).willReturn()

        let monitor = QuotaMonitor(probes: [mockProbe], observer: mockObserver)

        // When
        _ = try await monitor.refreshAll() // First: healthy
        _ = try await monitor.refreshAll() // Second: warning

        // Then
        verify(mockObserver).onStatusChanged(
            provider: .value(.claude),
            oldStatus: .value(.healthy),
            newStatus: .value(.warning)
        ).called(.once)
    }

    // MARK: - Accessing Current Snapshots

    @Test
    func `monitor stores and returns current snapshot for provider`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(snapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])
        _ = try await monitor.refreshAll()

        // When
        let currentSnapshot = await monitor.snapshot(for: .claude)

        // Then
        #expect(currentSnapshot?.quota(for: .session)?.percentRemaining == 50)
    }

    @Test
    func `monitor returns nil for provider without data`() async {
        // Given
        let monitor = QuotaMonitor(probes: [])

        // When
        let snapshot = await monitor.snapshot(for: .claude)

        // Then
        #expect(snapshot == nil)
    }

    // MARK: - Auto-Refresh

    @Test
    func `monitor can start continuous monitoring`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(snapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let stream = await monitor.startMonitoring(interval: .milliseconds(100))
        var events: [MonitoringEvent] = []

        // Collect first 2 events
        for await event in stream.prefix(2) {
            events.append(event)
        }

        await monitor.stopMonitoring()

        // Then
        #expect(events.count == 2)
        #expect(events.allSatisfy { event in
            if case .refreshed = event { return true }
            return false
        })
    }

    @Test
    func `monitor stops when requested`() async throws {
        // Given
        let mockProbe = MockUsageProbePort()
        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)],
            capturedAt: Date()
        )

        given(mockProbe).provider.willReturn(.claude)
        given(mockProbe).isAvailable().willReturn(true)
        given(mockProbe).probe().willReturn(snapshot)

        let monitor = QuotaMonitor(probes: [mockProbe])

        // When
        let stream = await monitor.startMonitoring(interval: .milliseconds(50))
        await monitor.stopMonitoring()

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }

        // Then - Stream should finish quickly after stop
        #expect(eventCount <= 2)
    }
}
