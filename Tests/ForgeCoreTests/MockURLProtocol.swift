import Foundation

/// Intercepts URLSession requests so food-database tests run against captured real responses
/// instead of the live network — deterministic, fast, and not dependent on rate limits or an
/// internet connection.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: [String: Data] = [:]
    /// Simulates a slow/cold-started source (e.g. Render free-tier spin-up) for timeout tests —
    /// keyed the same way as `responseData`, defaults to no delay.
    nonisolated(unsafe) static var responseDelay: [String: TimeInterval] = [:]

    static func stub(urlContains fragment: String, data: Data) {
        responseData[fragment] = data
    }

    static func stubDelayed(urlContains fragment: String, data: Data, delay: TimeInterval) {
        responseData[fragment] = data
        responseDelay[fragment] = delay
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        guard let (fragment, data) = Self.responseData.first(where: { url.contains($0.key) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let respond = { [weak self] in
            guard let self, let requestURL = self.request.url else { return }
            let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if let delay = Self.responseDelay[fragment], delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
