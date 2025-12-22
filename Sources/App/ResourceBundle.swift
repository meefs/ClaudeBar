import Foundation

/// Custom resource bundle accessor that works for both SPM development builds
/// and packaged macOS app bundles.
///
/// SPM's auto-generated `Bundle.module` looks at the app bundle root,
/// but macOS code signing requires resources in `Contents/Resources/`.
/// This accessor checks both locations.
enum ResourceBundle {
    static let bundle: Bundle = {
        let bundleName = "ClaudeBar_ClaudeBar.bundle"

        // For packaged app: look in Contents/Resources/
        // Bundle.main.resourceURL is Contents/Resources for .app bundles
        if let resourceURL = Bundle.main.resourceURL {
            let appBundlePath = resourceURL.appendingPathComponent(bundleName).path
            if let bundle = Bundle(path: appBundlePath) {
                return bundle
            }
        }

        // Fallback: use SPM's Bundle.module (works during development)
        return Bundle.module
    }()
}