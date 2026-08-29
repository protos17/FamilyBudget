import Foundation

/// `URLProtocol` stub for testing `GlobalSettingsViewModel.testAIConnection()` without hitting the network.
/// Tests using this must run serialized, since the stub is shared static state.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
        let error: Error?

        init(statusCode: Int = 200, data: Data = Data(), error: Error? = nil) {
            self.statusCode = statusCode
            self.data = data
            self.error = error
        }
    }

    nonisolated(unsafe) static var stub: Stub?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
