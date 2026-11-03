import Foundation

/// Token exchanges do not forward credential forms through redirects, cookies,
/// caches or credential storage. Bound the decoded body before token decoding.
enum OAuthTokenTransport {
    static func data(for request: URLRequest, authorizing: @MainActor () -> Bool) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard let body = request.httpBody, !body.isEmpty, body.count <= 256_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 35
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await submit(session: session, request: request, authorizing: authorizing)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard response.expectedContentLength <= 128_000 else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 128_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, response)
    }

    @MainActor private static func submit(session: URLSession, request: URLRequest,
                                          authorizing: @MainActor () -> Bool) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try Task.checkCancellation()
        guard authorizing() else { throw ProviderAuthorizationRevision.Changed.configuration }
        return try await session.bytes(for: request)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
