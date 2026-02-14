import Foundation
import Network
import Domain

/// Lightweight HTTP server using Network.framework (NWListener).
/// Listens on localhost only, receives hook events via POST /hook.
public final class HookHTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private var continuation: AsyncStream<SessionEvent>.Continuation?
    private let defaultPort: UInt16

    /// The actual port the server is listening on
    public private(set) var actualPort: UInt16 = 0

    public init(defaultPort: UInt16 = 19847) {
        self.defaultPort = defaultPort
    }

    /// Starts the HTTP server and returns a stream of parsed session events.
    public func start() async throws -> AsyncStream<SessionEvent> {
        let stream = AsyncStream<SessionEvent> { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in
                self.stop()
            }
        }

        // Try default port first, fall back to auto-assign
        let port: NWEndpoint.Port
        if let preferredPort = NWEndpoint.Port(rawValue: defaultPort) {
            port = preferredPort
        } else {
            port = .any
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: port)

        let listener = try NWListener(using: parameters)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let actualPort = listener.port?.rawValue {
                    self?.actualPort = actualPort
                    try? PortDiscovery.writePort(Int(actualPort))
                    AppLog.hooks.info("Hook HTTP server listening on port \(actualPort)")
                }
            case .failed(let error):
                AppLog.hooks.error("Hook HTTP server failed: \(error.localizedDescription)")
                self?.continuation?.finish()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .utility))
        self.listener = listener

        return stream
    }

    /// Stops the HTTP server and cleans up.
    public func stop() {
        listener?.cancel()
        listener = nil
        continuation?.finish()
        continuation = nil
        PortDiscovery.removePortFile()
        AppLog.hooks.info("Hook HTTP server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        // Read up to 64KB (more than enough for hook payloads)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            defer {
                // Send minimal HTTP 200 response and close
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(
                    content: response.data(using: .utf8),
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    }
                )
            }

            guard let data, error == nil else {
                if let error {
                    AppLog.hooks.debug("Connection error: \(error.localizedDescription)")
                }
                return
            }

            self?.processHTTPRequest(data)
        }
    }

    private func processHTTPRequest(_ rawData: Data) {
        // Find the body by looking for \r\n\r\n separator
        guard let rawString = String(data: rawData, encoding: .utf8) else { return }

        guard let separatorRange = rawString.range(of: "\r\n\r\n") else {
            AppLog.hooks.debug("No HTTP body found in request")
            return
        }

        let headerPart = rawString[rawString.startIndex..<separatorRange.lowerBound]

        // Only accept POST /hook
        guard headerPart.hasPrefix("POST /hook") else {
            AppLog.hooks.debug("Rejected non-POST /hook request")
            return
        }

        let bodyString = rawString[separatorRange.upperBound...]
        guard let bodyData = bodyString.data(using: .utf8) else { return }

        if let event = SessionEventParser.parse(bodyData) {
            AppLog.hooks.info("Received hook event: \(event.eventName.rawValue) for session \(event.sessionId)")
            continuation?.yield(event)
        } else {
            AppLog.hooks.warning("Failed to parse hook event payload")
        }
    }
}
