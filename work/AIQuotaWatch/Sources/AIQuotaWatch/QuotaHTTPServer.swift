import Foundation
import Network

final class QuotaHTTPServer: @unchecked Sendable {
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "AIQuotaWatch.HTTPServer")
    private var listener: NWListener?
    private var lastStatusData: Data?
    private var lastStatusAt = Date.distantPast
    private let statusCacheInterval: TimeInterval = 30

    init(port: UInt16 = 17_676) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    NSLog("AIQuotaWatch HTTP server failed: %@", String(describing: error))
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            NSLog("AIQuotaWatch web server listening on port %@", "\(port.rawValue)")
        } catch {
            NSLog("AIQuotaWatch failed to start web server: %@", String(describing: error))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                NSLog("AIQuotaWatch HTTP receive error: %@", String(describing: error))
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            self.respond(to: data, on: connection)
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        let request = String(decoding: requestData, as: UTF8.self)
        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
            send(status: "400 Bad Request", body: "Bad Request", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", body: "Bad Request", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        let method = String(parts[0])
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"

        if method == "OPTIONS" {
            send(status: "204 No Content", body: Data(), contentType: "text/plain", on: connection)
            return
        }

        guard method == "GET" else {
            send(status: "405 Method Not Allowed", body: "Method Not Allowed", contentType: "text/plain; charset=utf-8", on: connection)
            return
        }

        switch path {
        case "/", "/index.html":
            send(status: "200 OK", body: WebClientAssets.html, contentType: "text/html; charset=utf-8", on: connection)
        case "/styles.css":
            send(status: "200 OK", body: WebClientAssets.css, contentType: "text/css; charset=utf-8", on: connection)
        case "/app.js":
            send(status: "200 OK", body: WebClientAssets.javascript, contentType: "application/javascript; charset=utf-8", on: connection)
        case "/manifest.webmanifest":
            send(status: "200 OK", body: WebClientAssets.manifest, contentType: "application/manifest+json; charset=utf-8", on: connection)
        case "/favicon.svg":
            send(status: "200 OK", body: WebClientAssets.favicon, contentType: "image/svg+xml; charset=utf-8", on: connection)
        case "/api/status", "/api/status.json":
            sendStatusJSON(on: connection)
        case "/health":
            send(status: "200 OK", body: #"{"ok":true}"#, contentType: "application/json; charset=utf-8", on: connection)
        default:
            send(status: "404 Not Found", body: "Not Found", contentType: "text/plain; charset=utf-8", on: connection)
        }
    }

    private func sendStatusJSON(on connection: NWConnection) {
        do {
            if let data = reusableStatusData() {
                send(status: "200 OK", body: data, contentType: "application/json; charset=utf-8", on: connection)
                return
            }

            let snapshot = QuotaScanner.scan(now: Date())
            let payload = StatusPayloadBuilder.payload(from: snapshot)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(
                at: StatusFileWriter.statusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: StatusFileWriter.statusURL, options: .atomic)
            lastStatusData = data
            lastStatusAt = Date()
            send(status: "200 OK", body: data, contentType: "application/json; charset=utf-8", on: connection)
        } catch {
            let fallback = #"{"schemaVersion":2,"summary":"等待 Mac 端刷新","providers":[]}"#
            send(status: "503 Service Unavailable", body: fallback, contentType: "application/json; charset=utf-8", on: connection)
        }
    }

    private func reusableStatusData() -> Data? {
        if let lastStatusData,
           Date().timeIntervalSince(lastStatusAt) < statusCacheInterval {
            return lastStatusData
        }

        guard let fileData = try? Data(contentsOf: StatusFileWriter.statusURL),
              let object = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any],
              (object["schemaVersion"] as? Int) == 2,
              let scannedAt = object["scannedAt"] as? Int else {
            return nil
        }

        if Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(scannedAt))) < statusCacheInterval {
            lastStatusData = fileData
            lastStatusAt = Date()
            return fileData
        }

        return nil
    }

    private func send(status: String, body: String, contentType: String, on connection: NWConnection) {
        send(status: status, body: Data(body.utf8), contentType: contentType, on: connection)
    }

    private func send(status: String, body: Data, contentType: String, on connection: NWConnection) {
        var response = Data()
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        response.append(Data(headers.utf8))
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
