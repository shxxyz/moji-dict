import SwiftUI

struct CommentsSection: View {
    let wordID: String
    let accountSession: AccountSession?
    @StateObject private var model = CommentListModel()

    private struct Context: Equatable {
        let wordID: String
        let account: AccountSession?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text("评论")
                if model.count > 0 {
                    Text("\(model.count)")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)

            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    CommentRow(comment: comment)
                    if let replies = comment.sub, !replies.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(replies.comments) { reply in
                                CommentRow(comment: reply)
                            }
                            if replies.count > replies.comments.count {
                                Text("共 \(replies.count) 条回复，显示前 \(replies.comments.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在载入评论")
            } else if let error = model.errorMessage {
                HStack {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("重试") { Task { await model.loadMore() } }
                }
            } else if model.comments.isEmpty {
                Text("暂无评论")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else if model.hasMore {
                Button("加载更多评论") { Task { await model.loadMore() } }
                    .controlSize(.small)
            }
        }
        .task(id: Context(wordID: wordID, account: accountSession)) {
            await model.reload(wordID: wordID)
        }
    }
}

private struct CommentRow: View {
    let comment: WordComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(comment.author?.displayName ?? "MOJi 用户")
                if let recipient = comment.replyTo {
                    Text("回复 \(recipient.displayName)")
                }
                Spacer(minLength: 4)
                if let date = comment.date {
                    Text(date, format: .dateTime.year().month().day())
                }
                if let likes = comment.likedNum, likes > 0 {
                    Label("\(likes)", systemImage: "hand.thumbsup")
                        .accessibilityLabel("\(likes) 人点赞")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Text(displayContent)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayContent: String {
        guard let content = comment.content, !content.isEmpty else {
            return "（无文字内容）"
        }
        return content
    }
}
