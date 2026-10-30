import Foundation
import XCTest
@testable import MojiQuickLook

final class WordCommentsTests: XCTestCase {
    func testCommentRequestReusesAppSessionWithoutBrowserCookies() throws {
        let request = try MojiAPIClient.wordCommentsRequest(
            id: "198981419", page: 2, deviceID: "test-device", sessionToken: "test-session"
        )
        XCTAssertEqual(request.url?.path, "/parse/functions/comment-list")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Parse-Session-Token"), "test-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Parse-Installation-Id"), "test-device")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["targetId"] as? String, "198981419")
        XCTAssertEqual(body["targetType"] as? Int, 102)
        XCTAssertEqual(body["page"] as? Int, 2)
        XCTAssertEqual(body["limit"] as? Int, 20)
        XCTAssertEqual(body["subLimit"] as? Int, 3)
    }

    func testCapturedShapeDecodesRepliesAndMissingOptionalFields() throws {
        let data = Data("""
        {"result":{"code":200,"result":{
          "comments":[{"objectId":"c1","author":{"name":"作者"},"content":"评论正文",
            "createdAt":"2026-09-12T11:22:33.123Z","likedNum":8,
            "sub":{"comments":[{"objectId":"r1","replyTo":{"name":"作者"},"content":"回复"}],
                   "count":1,"page":0,"limit":3}}],
          "count":1,"page":1,"limit":20,"totalCount":2
        }}}
        """.utf8)
        let response = try JSONDecoder().decode(CommentListResponse.self, from: data)
        let page = try XCTUnwrap(response.result.result)
        XCTAssertFalse(page.hasMore)
        let comment = try XCTUnwrap(page.comments.first)
        XCTAssertNotNil(comment.date)
        XCTAssertEqual(comment.author?.displayName, "作者")
        XCTAssertEqual(comment.sub?.comments.first?.replyTo?.displayName, "作者")
        XCTAssertNil(comment.sub?.comments.first?.likedNum)
    }

    func testClientUsesRestoredSessionAndRemovesItOnLogout() async throws {
        let api = makeAPI()
        await api.restoreSession(token: "test-session", deviceID: "test-device")
        let authenticated = try await api.wordComments(id: "authentication")
        XCTAssertEqual(authenticated.comments.first?.content, "test-session")
        await api.logout()
        let anonymous = try await api.wordComments(id: "authentication")
        XCTAssertEqual(anonymous.comments.first?.content, "anonymous")
    }

    @MainActor
    func testPaginationUsesTopLevelCountAndResetsOnWordChange() async throws {
        let model = CommentListModel(api: makeAPI())
        await model.reload(wordID: "pagination")
        XCTAssertEqual(model.comments.count, 20)
        XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.comments.count, 39)
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.errorMessage)
        await model.reload(wordID: "empty")
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testExpiredSessionShowsErrorAndRetryUsesNewSession() async throws {
        let api = makeAPI()
        await api.restoreSession(token: "expired", deviceID: "test-device")
        let model = CommentListModel(api: api)
        await model.reload(wordID: "authentication")
        XCTAssertEqual(model.errorMessage, MojiAPIError.commentsSessionExpired.localizedDescription)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.isLoading)
        await api.restoreSession(token: "test-session", deviceID: "test-device")
        await model.loadMore()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.comments.count, 1)
    }

    func testFunctionFailureIsNotTreatedAsEmptyComments() async throws {
        do {
            _ = try await makeAPI().wordComments(id: "failure")
            XCTFail("Expected function-level error")
        } catch {
            XCTAssertEqual(error.localizedDescription, MojiAPIError.commentsFailed.localizedDescription)
        }
    }

    func testLiveCommentsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set MOJI_LIVE_TESTS=1 to test the read-only comment endpoint.")
        }
        let api = MojiAPIClient()
        if ProcessInfo.processInfo.environment["MOJI_COMMENT_SESSION_TESTS"] == "1" {
            let account = try XCTUnwrap(AccountSessionStore.load(), "Saved MOJi session is required")
            await api.restoreSession(token: account.sessionToken, deviceID: account.deviceID)
        }
        let first = try await api.wordComments(id: "198981419")
        XCTAssertFalse(first.comments.isEmpty)
        if first.hasMore {
            let second = try await api.wordComments(id: "198981419", page: 2)
            XCTAssertEqual(second.page, 2)
            XCTAssertNotEqual(first.comments.first?.id, second.comments.first?.id)
        }
    }

    private func makeAPI() -> MojiAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommentStubProtocol.self]
        return MojiAPIClient(session: URLSession(configuration: configuration))
    }
}

private final class CommentStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let word = body["targetId"] as? String ?? ""
        let page = body["page"] as? Int ?? 1
        let token = request.value(forHTTPHeaderField: "X-Parse-Session-Token") ?? "anonymous"
        var status = 200
        let response: [String: Any]
        if token == "expired" {
            status = 400
            response = ["code":209, "error":"Invalid session token"]
        } else if word == "failure" {
            response = ["result":["code":500, "result":"Service unavailable"]]
        } else {
            let count = word == "pagination" ? 39 : (word == "empty" ? 0 : 1)
            let ids = word == "pagination" ? Array(((page - 1) * 20)..<min(page * 20, count)) : Array(0..<count)
            response = ["result":["code":200,"result":[
                "comments":ids.map { ["objectId":"c\($0)", "content":token] },
                "page":page,"limit":20,"count":count,"totalCount":count + 9
            ]]]
        }
        let encoded = try! JSONSerialization.data(withJSONObject: response)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: encoded)
        client?.urlProtocolDidFinishLoading(self)
    }
}
