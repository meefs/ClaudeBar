#if ENABLE_SPARKLE
import Sparkle
import SwiftUI

/// A wrapper around SPUUpdater for SwiftUI integration.
/// This class manages the Sparkle update lifecycle and provides
/// observable properties for UI binding.
@MainActor
@Observable
final class SparkleUpdater {
    /// The underlying Sparkle updater controller (nil if bundle is invalid)
    private var controller: SPUStandardUpdaterController?

    /// Whether an update check is currently in progress
    private(set) var isCheckingForUpdates = false

    /// Whether the updater is available (bundle is properly configured)
    var isAvailable: Bool {
        controller != nil
    }

    /// Whether updates can be checked (updater is configured and ready)
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// The date of the last update check
    var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        // Check if we're in a proper app bundle
        if Self.isProperAppBundle() {
            // Normal app bundle - initialize Sparkle
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            // Debug/development build - Sparkle won't work without proper bundle
            print("SparkleUpdater: Not running from app bundle, updater disabled")
        }
    }

    /// Manually check for updates
    func checkForUpdates() {
        guard let controller = controller, controller.updater.canCheckForUpdates else {
            return
        }
        controller.checkForUpdates(nil)
    }

    /// Check for updates in the background (no UI unless update found)
    func checkForUpdatesInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    /// Check if running from a proper .app bundle
    private static func isProperAppBundle() -> Bool {
        let bundle = Bundle.main

        // Check bundle path ends with .app
        guard bundle.bundlePath.hasSuffix(".app") else {
            return false
        }

        // Check required keys exist
        guard let info = bundle.infoDictionary,
              info["CFBundleIdentifier"] != nil,
              info["CFBundleVersion"] != nil,
              info["SUFeedURL"] != nil else {
            return false
        }

        return true
    }
}

// MARK: - SwiftUI Environment

/// Environment key for accessing the SparkleUpdater
private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SparkleUpdater? = nil
}

extension EnvironmentValues {
    @MainActor
    var sparkleUpdater: SparkleUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }
}
#endif
