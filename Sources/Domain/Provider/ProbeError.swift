import Foundation

/// Errors that can occur when probing a CLI
public enum ProbeError: Error, Equatable, Sendable, LocalizedError {
    /// The CLI binary was not found on the system
    case cliNotFound(String)

    /// User needs to log in to the CLI
    case authenticationRequired

    /// OAuth session has expired - user needs to re-authenticate
    case sessionExpired

    /// The CLI output could not be parsed
    case parseFailed(String)

    /// The probe timed out waiting for a response
    case timeout

    /// No quota data was available
    case noData

    /// The CLI needs to be updated
    case updateRequired

    /// User needs to trust the current folder
    case folderTrustRequired

    /// Command execution failed
    case executionFailed(String)

    /// Usage data requires a subscription plan (API billing accounts don't support /usage)
    case subscriptionRequired

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .cliNotFound(let binary):
            return "CLI not found: \(binary)"
        case .authenticationRequired:
            return "Authentication required. Please log in."
        case .sessionExpired:
            return "Session expired. Run `claude` in terminal to log in again."
        case .parseFailed(let reason):
            return "Failed to parse output: \(reason)"
        case .timeout:
            return "Request timed out"
        case .noData:
            return "No usage data available"
        case .updateRequired:
            return "CLI update required"
        case .folderTrustRequired:
            return "Please trust this folder in Claude CLI"
        case .executionFailed(let reason):
            return reason
        case .subscriptionRequired:
            return "Subscription required for usage data"
        }
    }
}
