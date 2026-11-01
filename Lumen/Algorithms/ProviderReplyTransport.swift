import Foundation

/// The non-streaming chat-completions contract used by the configured gateway.
/// Completion status and reference identity are separate from claim support.
enum ProviderReplyTransport {
    static let maxRequestBytes = 12_000_000
    static let maxResponseBytes = 1_000_000
    enum Failure: Error, Equatable {
        case requestSize, responseSize, http, malformed, incomplete, refusal, toolCall
    }

    static func text(in data: Data) throws -> String {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= maxResponseBytes else { throw Failure.responseSize }
        let root: LiteralJSON.Node
        do { root = try LiteralJSON.parse(data).root }
        catch is CancellationError { throw CancellationError() }
        catch { throw Failure.malformed }
        guard root.members != nil, absentOrNull(root["error"]),
              let choices = root["choices"]?.elements, choices.count == 1,
              choices[0]["index"]?.number == "0",
              let message = choices[0]["message"], message.members != nil,
              message["role"]?.string == "assistant" else { throw Failure.malformed }
        guard choices[0]["finish_reason"]?.string == "stop" else { throw Failure.incomplete }
        if let refusal = message["refusal"], !absentOrNull(refusal) {
            guard refusal.string == "" else { throw Failure.refusal }
        }
        guard absentOrNull(message["function_call"]),
              absentOrNull(message["tool_calls"]) || message["tool_calls"]?.elements?.isEmpty == true else { throw Failure.toolCall }
        guard let content = message["content"]?.string else { throw Failure.malformed }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.malformed }
        try Task.checkCancellation()
        return text
    }

    private static func absentOrNull(_ node: LiteralJSON.Node?) -> Bool {
        guard let node else { return true }
        if case .null = node.value { return true }
        return false
    }

    /// Accumulate at most the bounded decoded response body. Foundation/TLS
    /// buffers are separate; no whole-process memory ceiling is implied.
    static func send(_ request: URLRequest) async throws -> String {
        try Task.checkCancellation()
        guard let body = request.httpBody, !body.isEmpty, body.count <= maxRequestBytes else { throw Failure.requestSize }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var boundedRequest = request
        boundedRequest.timeoutInterval = min(60, request.timeoutInterval)
        boundedRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: boundedRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.http }
        guard response.expectedContentLength <= Int64(maxResponseBytes) else { throw Failure.responseSize }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maxResponseBytes else { throw Failure.responseSize }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try text(in: data)
    }

    // A configured endpoint must respond directly. Do not forward the health
    // request, body or authorization through a server-supplied redirect.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
