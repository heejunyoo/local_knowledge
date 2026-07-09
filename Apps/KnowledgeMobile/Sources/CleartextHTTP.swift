import Foundation
import Network

/// Minimal HTTP/1.1 client over raw TCP (Network.framework).
/// URLSession is subject to App Transport Security; NWConnection cleartext is not.
/// Used for Core gateway `http://100.x:8741` on Tailscale.
enum CleartextHTTP {
    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    static func request(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> Response {
        let scheme = (url.scheme ?? "http").lowercased()
        if scheme == "https" {
            return try await urlSessionRequest(method: method, url: url, headers: headers, body: body, timeout: timeout)
        }
        guard scheme == "http" else {
            throw NSError(domain: "http", code: -1, userInfo: [NSLocalizedDescriptionKey: "unsupported URL scheme"])
        }
        guard let host = url.host, !host.isEmpty else {
            throw URLError(.badURL)
        }
        let portNum = UInt16(url.port ?? 80)
        guard let nwPort = NWEndpoint.Port(rawValue: portNum) else {
            throw URLError(.badURL)
        }

        let path: String = {
            var p = url.path.isEmpty ? "/" : url.path
            if let q = url.query, !q.isEmpty { p += "?\(q)" }
            return p
        }()

        var headerLines: [String] = [
            "\(method.uppercased()) \(path) HTTP/1.1",
            "Host: \(host)\(url.port.map { ":\($0)" } ?? "")",
            "Connection: close",
            "Accept: application/json",
            "User-Agent: KnowledgeMobile/1.0",
        ]
        for (k, v) in headers {
            headerLines.append("\(k): \(v)")
        }
        let bodyData = body ?? Data()
        let m = method.uppercased()
        if m != "GET" && m != "HEAD" {
            headerLines.append("Content-Length: \(bodyData.count)")
            if headers.keys.first(where: { $0.lowercased() == "content-type" }) == nil {
                headerLines.append("Content-Type: application/json")
            }
        }
        var requestData = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        requestData.append(bodyData)

        return try await withCheckedThrowingContinuation { cont in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let state = ExchangeState(continuation: cont, connection: conn)
            let queue = DispatchQueue(label: "knowledge.cleartext.http")

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                state.finish(.failure(URLError(.timedOut)))
            }
            timer.resume()
            state.timer = timer

            conn.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    conn.send(content: requestData, completion: .contentProcessed { err in
                        if let err {
                            state.finish(.failure(err))
                            return
                        }
                        state.receiveLoop()
                    })
                case .failed(let err):
                    state.finish(.failure(err))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    fileprivate static func parseHTTP(_ data: Data) -> Response? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let statusLine = lines.first else { return nil }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let status = Int(parts[1]) else { return nil }
        var headers: [String: String] = [:]
        var contentLength: Int?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = val
            if key == "content-length" { contentLength = Int(val) }
        }
        let bodyStart = headerEnd.upperBound
        if let cl = contentLength {
            guard data.count >= bodyStart + cl else { return nil }
            let body = data.subdata(in: bodyStart..<(bodyStart + cl))
            return Response(status: status, headers: headers, body: body)
        }
        // No Content-Length: accept what we have only when connection will close (caller decides on isComplete)
        let body = data.subdata(in: bodyStart..<data.endIndex)
        return Response(status: status, headers: headers, body: body)
    }

    private static func urlSessionRequest(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return Response(status: status, headers: [:], body: data)
    }
}

private final class ExchangeState: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<CleartextHTTP.Response, Error>?
    private let connection: NWConnection
    private var buffer = Data()
    private var done = false
    var timer: DispatchSourceTimer?

    init(continuation: CheckedContinuation<CleartextHTTP.Response, Error>, connection: NWConnection) {
        self.cont = continuation
        self.connection = connection
    }

    func finish(_ result: Result<CleartextHTTP.Response, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let c = cont
        cont = nil
        lock.unlock()
        timer?.cancel()
        connection.cancel()
        guard let c else { return }
        switch result {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
    }

    func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.finish(.failure(error))
                return
            }
            self.lock.lock()
            if let data, !data.isEmpty { self.buffer.append(data) }
            let snap = self.buffer
            self.lock.unlock()

            if let parsed = CleartextHTTP.parseHTTP(snap) {
                // If Content-Length satisfied, parseHTTP returns; if no CL and not complete, may return early body — only accept no-CL when complete
                let hasCL = parsed.headers["content-length"] != nil
                if hasCL || isComplete {
                    self.finish(.success(parsed))
                    return
                }
            }
            if isComplete {
                if let parsed = CleartextHTTP.parseHTTP(snap) {
                    self.finish(.success(parsed))
                } else {
                    self.finish(.failure(URLError(.cannotParseResponse)))
                }
                return
            }
            self.receiveLoop()
        }
    }
}
