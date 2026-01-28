import Foundation
import Network
import os.log

/// HTTP server based on Apple's Network framework
public actor HTTPServer {
    private let listener: NWListener
    private let router: Router
    private let configuration: ServerConfiguration
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var isRunning = false
    private let logger = Logger(subsystem: "SwiftStoreServer", category: "HTTPServer")

    /// Initialize HTTP server
    /// - Parameters:
    ///   - router: Router to handle requests
    ///   - configuration: Server configuration
    public init(router: Router, configuration: ServerConfiguration) throws {
        self.router = router
        self.configuration = configuration

        let port = NWEndpoint.Port(integerLiteral: UInt16(configuration.port))
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            self.listener = try NWListener(using: params, on: port)
        } catch {
            throw HTTPError.internalError("Failed to create listener: \(error)")
        }
    }

    /// Start the server
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task {
                await self.handleListenerState(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }

        listener.start(queue: .global())

        // Wait a moment for the listener to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    /// Stop the server
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        // Close all connections
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()

        listener.cancel()
    }

    /// Handle listener state changes
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if configuration.host == "0.0.0.0", let ipAddress = getLocalIPAddress() {
                logger.info("Server listening on \(ipAddress):\(self.configuration.port)")
            } else {
                logger.info("Server listening on \(self.configuration.host):\(self.configuration.port)")
            }
        case .failed(let error):
            logger.error("Server failed: \(error.localizedDescription)")
        case .cancelled:
            logger.info("Server cancelled")
        default:
            break
        }
    }

    /// Handle new connection
    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task {
                await self.handleConnectionState(id: id, state: state)
            }
        }

        connection.start(queue: .global())
    }

    /// Handle connection state changes
    private func handleConnectionState(id: ObjectIdentifier, state: NWConnection.State) {
        switch state {
        case .ready:
            if let connection = connections[id] {
                Task {
                    await receiveRequest(connection, id: id)
                }
            }
        case .failed, .cancelled:
            connections.removeValue(forKey: id)
        default:
            break
        }
    }

    /// Receive and process HTTP request
    private func receiveRequest(_ connection: NWConnection, id: ObjectIdentifier) async {
        // Read request data
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            Task {
                await self.handleRequestData(data, connection: connection, id: id)
            }
        }
    }

    /// Handle received request data
    private func handleRequestData(_ data: Data, connection: NWConnection, id: ObjectIdentifier) async {
        do {
            let request = try HTTPRequestParser.parse(data)
            let response = await router.handle(request)
            await sendResponse(response, connection: connection)
        } catch let error as HTTPError {
            let response = HTTPResponse.error(error.localizedDescription, status: error.status, corsEnabled: configuration.enableCORS)
            await sendResponse(response, connection: connection)
        } catch {
            let response = HTTPResponse.error(error.localizedDescription, corsEnabled: configuration.enableCORS)
            await sendResponse(response, connection: connection)
        }
    }

    /// Send HTTP response
    private func sendResponse(_ response: HTTPResponse, connection: NWConnection) async {
        let data = response.build()

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Send error: \(error.localizedDescription)")
            }
            // Close connection after sending (HTTP/1.0 style for simplicity)
            connection.cancel()
        })
    }
}
