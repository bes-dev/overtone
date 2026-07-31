import Foundation
import Network

/// Minimal loopback HTTP listener. It knows about framing and nothing about speech —
/// requests are handed to `route`, which turns them into a response.
final class ControlServer {
    struct Request: Equatable {
        let method: String
        let path: String
        let body: Data
    }

    struct Response {
        let status: String
        let json: String
        var contentType = "application/json"

        static let notFound = Response(status: "404 Not Found", json: #"{"error":"not found"}"#)
        static let badRequest = Response(status: "400 Bad Request", json: #"{"error":"invalid request"}"#)
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "ai.overtone.control-http")
    private let route: (Request, @escaping (Response) -> Void) -> Void

    init(port: UInt16, route: @escaping (Request, @escaping (Response) -> Void) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!
        )
        listener = try NWListener(using: parameters)
        self.route = route
    }

    /// `onFailure` fires when the port cannot be taken — usually another copy already has it.
    func start(onFailure: @escaping (Error) -> Void) {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error) }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    /// Parses a complete request, or `nil` while headers or body are still on the wire.
    static func parse(_ data: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        let contentLength = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            ?? 0
        let bodyStart = headerRange.upperBound
        guard contentLength >= 0, data.count >= bodyStart + contentLength else { return nil }
        return Request(
            method: String(parts[0]).uppercased(),
            path: String(parts[1]).split(separator: "?").first.map(String.init) ?? "/",
            body: data.subdata(in: bodyStart..<(bodyStart + contentLength))
        )
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if let request = Self.parse(accumulated) {
                self.route(request) { [weak self] response in
                    self?.queue.async { self?.respond(connection, response) }
                }
            } else if complete || error != nil || accumulated.count > 1_048_576 {
                self.respond(connection, .badRequest)
            } else {
                self.receive(connection, buffer: accumulated)
            }
        }
    }

    private func respond(_ connection: NWConnection, _ response: Response) {
        let body = Data(response.json.utf8)
        let header = "HTTP/1.1 \(response.status)\r\nContent-Type: \(response.contentType)\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }
}
