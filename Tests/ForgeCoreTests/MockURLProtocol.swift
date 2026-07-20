import Foundation

/// Intercepts URLSession requests so food-database tests run against captured real responses
/// instead of the live network — deterministic, fast, and not dependent on rate limits or an
/// internet connection.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: [String: Data] = [:]

    static func stub(urlContains fragment: String, data: Data) {
        responseData[fragment] = data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        guard let (_, data) = Self.responseData.first(where: { url.contains($0.key) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
