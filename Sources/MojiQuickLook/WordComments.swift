import Foundation

struct CommentListResponse: Decodable, Sendable {
    let result: FunctionResult

    struct FunctionResult: Decodable, Sendable {
        let code: Int
        let result: CommentPage?

        private enum CodingKeys: String, CodingKey { case code, result }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            code = try values.decode(Int.self, forKey: .code)
            result = code == 200 ? try values.decode(CommentPage.self, forKey: .result) : nil
        }
    }
}

struct CommentPage: Decodable, Sendable {
    let comments: [WordComment]
    let count: Int
    let page: Int
    let limit: Int
    let totalCount: Int?

    // count is the number of top-level comments; totalCount includes replies.
    var hasMore: Bool {
        !comments.isEmpty && limit > 0 && page * limit < count
    }
}

struct CommentAuthor: Decodable, Sendable {
    let name: String?

    var displayName: String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "MOJi 用户" : name
    }
}

struct WordComment: Decodable, Identifiable, Sendable {
    let objectId: String
    let content: String?
    let author: CommentAuthor?
    let replyTo: CommentAuthor?
    let createdAt: String?
    let likedNum: Int?
    let sub: CommentPage?

    var id: String { objectId }
    var date: Date? {
        guard let createdAt else { return nil }
        return (try? Date(createdAt, strategy: .iso8601
            .year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
            ?? (try? Date(createdAt, strategy: .iso8601))
    }
}

@MainActor
final class CommentListModel: ObservableObject {
    @Published private(set) var comments: [WordComment] = []
    @Published private(set) var count = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?

    private let api: MojiAPIClient
    private var wordID: String?
    private var nextPage = 1
    private var generation = UUID()

    init(api: MojiAPIClient = .shared) { self.api = api }

    func reload(wordID: String) async {
        generation = UUID()
        self.wordID = wordID
        comments = []
        count = 0
        nextPage = 1
        hasMore = true
        isLoading = false
        errorMessage = nil
        await loadMore()
    }

    func loadMore() async {
        guard let wordID, !isLoading, hasMore else { return }
        let requestedGeneration = generation
        let requestedPage = nextPage
        isLoading = true
        errorMessage = nil
        defer {
            if generation == requestedGeneration { isLoading = false }
        }
        do {
            let response = try await api.wordComments(id: wordID, page: requestedPage)
            try Task.checkCancellation()
            guard generation == requestedGeneration else { return }
            var knownIDs = Set(comments.map(\.id))
            comments.append(contentsOf: response.comments.filter {
                knownIDs.insert($0.id).inserted
            })
            count = response.count
            nextPage = requestedPage + 1
            hasMore = response.hasMore
        } catch {
            guard generation == requestedGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
