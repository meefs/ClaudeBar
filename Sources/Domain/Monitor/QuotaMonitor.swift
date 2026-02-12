import Foundation
import Observation

/// Events emitted during continuous monitoring
public enum MonitoringEvent: Sendable {
    /// A refresh cycle completed
    case refreshed
    /// An error occurred during refresh for a provider
    case error(providerId: String, Error)
}

/// The main domain service that coordinates quota monitoring across AI providers.
/// Providers are rich domain models that own their own snapshots.
/// QuotaMonitor coordinates refreshes and alerts users when status changes.
@Observable
public final class QuotaMonitor: @unchecked Sendable {
    /// The providers repository (internal - access via delegation methods)
    private let providers: any AIProviderRepository

    /// Optional alerter for quota changes (e.g., system notifications)
    private let alerter: (any QuotaAlerter)?

    /// Clock for scheduling intervals (injectable for tests)
    private let clock: any Clock

    /// Previous status for change detection
    private var previousStatuses: [String: QuotaStatus] = [:]

    /// Current monitoring task
    private var monitoringTask: Task<Void, Never>?

    /// Whether monitoring is active
    public private(set) var isMonitoring: Bool = false

    /// The currently selected provider IDs (for UI display, supports multi-select)
    public var selectedProviderIds: Set<String> = ["claude"]

    /// Backward-compatible single-select accessor
    public var selectedProviderId: String {
        get { selectedProviderIds.first ?? "claude" }
        set { selectedProviderIds = [newValue] }
    }

    // MARK: - Initialization

    /// Creates a QuotaMonitor with a provider repository.
    /// Automatically validates the selected provider on initialization.
    public init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil,
        clock: any Clock
    ) {
        self.providers = providers
        self.alerter = alerter
        self.clock = clock
        selectFirstEnabledIfNeeded()
    }

    // MARK: - Monitoring Operations

    /// Refreshes all enabled providers concurrently.
    /// Each provider updates its own snapshot.
    /// Disabled providers are skipped.
    public func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers.enabled {
                group.addTask {
                    await self.refreshProvider(provider)
                }
            }
        }
    }

    /// Refreshes a single provider
    private func refreshProvider(_ provider: any AIProvider) async {
        guard await provider.isAvailable() else {
            return
        }

        do {
            let snapshot = try await provider.refresh()
            await handleSnapshotUpdate(provider: provider, snapshot: snapshot)
        } catch {
            // Provider stores error in lastError - no need for external observer
        }
    }

    /// Handles snapshot update and alerts user if status changed
    private func handleSnapshotUpdate(provider: any AIProvider, snapshot: UsageSnapshot) async {
        let previousStatus = previousStatuses[provider.id] ?? .healthy
        let newStatus = snapshot.overallStatus

        previousStatuses[provider.id] = newStatus

        // Alert user only if status changed
        if previousStatus != newStatus, let alerter = alerter {
            await alerter.alert(
                providerId: provider.id,
                previousStatus: previousStatus,
                currentStatus: newStatus
            )
        }
    }

    /// Refreshes a single provider by its ID.
    public func refresh(providerId: String) async {
        guard let provider = providers.provider(id: providerId) else {
            return
        }
        await refreshProvider(provider)
    }

    /// Refreshes all enabled providers except the specified one.
    public func refreshOthers(except providerId: String) async {
        let otherProviders = providers.enabled.filter { $0.id != providerId }

        await withTaskGroup(of: Void.self) { group in
            for provider in otherProviders {
                group.addTask {
                    await self.refreshProvider(provider)
                }
            }
        }
    }

    // MARK: - Queries

    /// Returns the provider with the given ID
    public func provider(for id: String) -> (any AIProvider)? {
        providers.provider(id: id)
    }

    /// Returns all providers
    public var allProviders: [any AIProvider] {
        providers.all
    }

    /// Returns only enabled providers
    public var enabledProviders: [any AIProvider] {
        providers.enabled
    }

    /// Adds a provider dynamically
    public func addProvider(_ provider: any AIProvider) {
        providers.add(provider)
    }

    /// Removes a provider by ID
    public func removeProvider(id: String) {
        providers.remove(id: id)
    }

    /// Returns the lowest quota across all enabled providers
    public func lowestQuota() -> UsageQuota? {
        providers.enabled
            .compactMap(\.snapshot?.lowestQuota)
            .min()
    }

    /// Returns the overall status across enabled providers (worst status wins)
    public var overallStatus: QuotaStatus {
        providers.enabled
            .compactMap(\.snapshot?.overallStatus)
            .max() ?? .healthy
    }

    // MARK: - Selection

    /// All selected providers (from enabled providers, preserving providers order)
    public var selectedProviders: [any AIProvider] {
        providers.enabled.filter { selectedProviderIds.contains($0.id) }
    }

    /// The currently selected provider (first selected, for backward compat)
    public var selectedProvider: (any AIProvider)? {
        selectedProviders.first
    }

    /// Status across all selected providers (worst status wins, for menu bar icon)
    public var selectedProviderStatus: QuotaStatus {
        selectedProviders
            .compactMap(\.snapshot?.overallStatus)
            .max() ?? .healthy
    }

    /// Whether any provider is currently refreshing
    public var isRefreshing: Bool {
        providers.all.contains { $0.isSyncing }
    }

    /// Toggles a provider in/out of the multi-select set.
    /// Cannot deselect the last provider.
    public func toggleProviderSelection(id: String) {
        guard providers.enabled.contains(where: { $0.id == id }) else { return }
        if selectedProviderIds.contains(id) {
            guard selectedProviderIds.count > 1 else { return }
            selectedProviderIds.remove(id)
        } else {
            selectedProviderIds.insert(id)
        }
    }

    /// Selects a provider by ID, replacing the entire selection (must be enabled)
    public func selectProvider(id: String) {
        if providers.enabled.contains(where: { $0.id == id }) {
            selectedProviderIds = [id]
        }
    }

    /// Sets a provider's enabled state.
    /// When disabling a selected provider, removes it from the selection.
    /// If no providers remain selected, auto-selects the first enabled.
    public func setProviderEnabled(_ id: String, enabled: Bool) {
        guard let provider = providers.provider(id: id) else { return }
        provider.isEnabled = enabled
        if !enabled {
            selectedProviderIds.remove(id)
            if selectedProviderIds.isEmpty {
                selectFirstEnabledIfNeeded()
            }
        }
    }

    /// Selects the first enabled provider if current selection is invalid.
    /// Called automatically during initialization and when providers are disabled.
    private func selectFirstEnabledIfNeeded() {
        let enabledIds = Set(providers.enabled.map(\.id))
        let validSelection = selectedProviderIds.intersection(enabledIds)
        if validSelection.isEmpty, let firstEnabled = providers.enabled.first {
            selectedProviderIds = [firstEnabled.id]
        } else {
            selectedProviderIds = validSelection
        }
    }

    // MARK: - Continuous Monitoring

    /// Starts continuous monitoring at the specified interval.
    /// Returns an AsyncStream of monitoring events.
    public func startMonitoring(interval: Duration = .seconds(60)) -> AsyncStream<MonitoringEvent> {
        // Stop any existing monitoring
        monitoringTask?.cancel()

        isMonitoring = true

        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await self.refreshAll()
                    continuation.yield(.refreshed)

                    do {
                        try await clock.sleep(for: interval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }

            self.monitoringTask = task

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Stops continuous monitoring
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}
