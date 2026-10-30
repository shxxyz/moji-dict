import Foundation
import XCTest
@testable import MojiQuickLook

final class MojiTransportTests: XCTestCase {
    func testGatewayDenialIsNotReportedAsIncorrectPassword() async throws {
        for scenario in ["gateway", "unavailable", "limited", "credentials"] {
            let api = makeAPI(scenario)
            do {
                _ = try await api.login(email: "", password: "")
                XCTFail("Expected login failure")
            } catch let error as MojiAPIError {
                switch (scenario, error) {
                case ("gateway", .requestBlocked), ("unavailable", .httpStatus(503)),
                     ("limited", .rateLimited):
                    break
                case ("credentials", .authenticationFailed(let message)):
                    XCTAssertEqual(message, "Invalid credentials")
                default:
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testGatewayDenialDoesNotExpireCommentSession() async throws {
        let api = makeAPI("gateway")
        await api.restoreSession(token: "test-token", deviceID: "test-device")
        do {
            _ = try await api.wordComments(id: "test")
            XCTFail("Expected gateway denial")
        } catch let error as MojiAPIError {
            guard case .requestBlocked = error else {
                return XCTFail("Gateway denial must not be reported as session expiration")
            }
        }
    }

    func testSearchGatewayDenialIsIdentified() async throws {
        do {
            _ = try await makeAPI("gateway").search("test")
            XCTFail("Expected gateway denial")
        } catch let error as MojiAPIError {
            guard case .requestBlocked = error else {
                return XCTFail("Expected gateway error")
            }
        }
    }

    func testLiveLoginValidationWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Enable read-only live endpoint validation.")
        }
        // Empty credentials exercise request validation without attempting
        // authentication against any real account.
        do {
            _ = try await MojiAPIClient().login(email: "", password: "")
            XCTFail("Empty credentials must not authenticate")
        } catch let error as MojiAPIError {
            guard case .authenticationFailed(let message) = error else {
                return XCTFail("Request did not reach the login service: \(error)")
            }
            XCTAssertNotNil(message)
        }
    }

    private func makeAPI(_ scenario: String) -> MojiAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransportStub.self]
        configuration.httpAdditionalHeaders = ["X-Test-Scenario": scenario]
        return MojiAPIClient(session: URLSession(configuration: configuration))
    }
}

private final class TransportStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let status: Int
        let contentType: String
        let body: String
        switch request.value(forHTTPHeaderField: "X-Test-Scenario") {
        case "credentials":
            status = 401
            contentType = "application/json"
            body = #"{"message":"Invalid credentials"}"#
        case "unavailable":
            status = 503
            contentType = "text/html"
            body = "<html>Service unavailable</html>"
        case "limited":
            status = 429
            contentType = "application/json"
            body = #"{"message":"Too many requests"}"#
        default:
            status = 403
            contentType = "text/html; charset=utf-8"
            body = "<html>Sorry, you have been blocked. Denied by http_custom</html>"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
