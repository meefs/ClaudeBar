import Foundation
import Observation

/// GitHub Copilot AI provider - a rich domain model.
/// Observable class with its own state (isSyncing, snapshot, error).
/// Owns its probe, credentials, and manages its own data lifecycle.
@Observable
public final class CopilotProvider: AIProvider, @unchecked Sendable {
    // MARK: - Identity (Protocol Requirement)

    public let id: String = "copilot"
    public let name: String = "Copilot"
    public let cliCommand: String = "gh"

    public var dashboardURL: URL? {
        URL(string: "https://github.com/settings/billing/summary")
    }

    public var statusPageURL: URL? {
        URL(string: "https://www.githubstatus.com")
    }

    /// Whether the provider is enabled (persisted via settingsRepository, defaults to false - requires setup)
    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    // MARK: - State (Observable)

    /// Whether the provider is currently syncing data
    public private(set) var isSyncing: Bool = false

    /// The current usage snapshot (nil if never refreshed or unavailable)
    public private(set) var snapshot: UsageSnapshot?

    /// The last error that occurred during refresh
    public private(set) var lastError: Error?

    // MARK: - Credentials (Observable)

    /// The GitHub username for API calls
    public var username: String {
        didSet {
            credentialStore.save(username, forKey: CredentialKey.githubUsername)
        }
    }

    /// Whether a GitHub token is configured
    public var hasToken: Bool {
        credentialStore.exists(forKey: CredentialKey.githubToken)
    }

    // MARK: - Internal

    /// The probe used to fetch usage data
    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository
    private let credentialStore: any CredentialStore

    // MARK: - Initialization

    /// Creates a Copilot provider with the specified dependencies
    /// - Parameters:
    ///   - probe: The probe to use for fetching usage data
    ///   - settingsRepository: The repository for persisting settings
    ///   - credentialStore: The store for credentials (token, username)
    public init(
        probe: any UsageProbe,
        settingsRepository: any ProviderSettingsRepository,
        credentialStore: any CredentialStore
    ) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.credentialStore = credentialStore
        // Copilot defaults to false (requires setup)
        self.isEnabled = settingsRepository.isEnabled(forProvider: "copilot", defaultValue: false)
        // Load persisted username
        self.username = credentialStore.get(forKey: CredentialKey.githubUsername) ?? ""
    }

    // MARK: - Credential Management

    /// Saves the GitHub token
    public func saveToken(_ token: String) {
        credentialStore.save(token, forKey: CredentialKey.githubToken)
    }

    /// Retrieves the GitHub token
    public func getToken() -> String? {
        credentialStore.get(forKey: CredentialKey.githubToken)
    }

    /// Deletes the GitHub token and username
    public func deleteCredentials() {
        credentialStore.delete(forKey: CredentialKey.githubToken)
        credentialStore.delete(forKey: CredentialKey.githubUsername)
        username = ""
    }

    // MARK: - AIProvider Protocol

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    /// Refreshes the usage data and updates the snapshot.
    /// Sets isSyncing during refresh and captures any errors.
    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }
}
