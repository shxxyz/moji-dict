import SwiftUI

struct ContentView: View {
    @StateObject private var model = SearchViewModel()
    @StateObject private var account = AccountViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 270, ideal: 330, max: 430)
        } detail: {
            detailPane
                .frame(minWidth: 560, minHeight: 520)
        }
        .navigationTitle("Moji 辞書")
        .searchable(
            text: $model.query,
            placement: .toolbar,
            prompt: "输入日语、假名、罗马音或中文"
        )
        .onSubmit(of: .search) {
            model.searchImmediately()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        model.goBack()
                    } label: {
                        Label("后退", systemImage: "chevron.left")
                    }
                    .disabled(!model.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)

                    Button {
                        model.goForward()
                    } label: {
                        Label("前进", systemImage: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                }
                .labelStyle(.iconOnly)
                .controlGroupStyle(.navigation)
                .help("前进或后退浏览查询记录")
            }

            ToolbarItem(placement: .primaryAction) {
                AccountToolbarControl(account: account)
            }
        }
        .sheet(isPresented: $account.isLoginSheetPresented) {
            LoginView(account: account)
        }
        .onChange(of: account.session != nil) {
            model.retryDetail()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("结果类型", selection: $model.filter) {
                ForEach(ResultFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .padding(10)

            if model.query.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.searchError {
                ContentUnavailableView {
                    Label("查询失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        model.searchImmediately()
                    }
                }
            } else if !model.isSearching && model.visibleResults.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleResults) { result in
                        SearchResultRow(result: result)
                            .tag(result.id)
                    }
                }
                .listStyle(.sidebar)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let result = model.selectedResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ResultHeader(result: result, word: model.detail?.word)
                        .padding(.bottom, 18)

                    if result.category == .word {
                        if let detail = model.detail {
                            WordDetailView(
                                detail: detail,
                                related: model.related,
                                forvoAudio: model.forvoAudio
                            ) { spell in
                                model.filter = .word
                                model.query = spell
                            }
                        } else if model.isLoadingDetail {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressView()
                                Text("正在载入完整释义…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = model.detailError {
                            ErrorDetailView(message: error) {
                                model.retryDetail()
                            }
                        }
                    } else {
                        SearchPreviewView(result: result)
                    }

                    if result.category == .word {
                        CommentsSection(wordID: result.targetId, accountSession: account.session)
                            .padding(.top, 30)

                        ExternalLookupButtons(
                            result: result,
                            headword: model.detail?.word?.spell ?? result.headword
                        )
                        .padding(.top, 30)
                    }

                    SourceNotice()
                        .padding(.top, 18)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 52)
                .padding(.vertical, 38)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        Text(result.sidebarTitle)
            .font(.callout)
            .fontWeight(.regular)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}

private struct ResultHeader: View {
    let result: SearchResult
    let word: WordInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                HeadwordText(
                    base: word?.spell ?? result.headword,
                    pronunciation: headerPronunciation
                )
                .fixedSize()

                if let accent = word?.accent, !accent.isEmpty {
                    Text(accent)
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .foregroundStyle(.secondary)
                        .padding(.top, headerPronunciation == nil ? 1 : 10)
                }
            }

            if let word, !word.tagList.isEmpty {
                Text(word.tagLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var headerPronunciation: String? {
        let base = word?.spell ?? result.headword
        let pronunciation = word?.pron ?? result.pronunciation
        guard
            let pronunciation,
            !pronunciation.isEmpty,
            pronunciation != base,
            base.containsKanji
        else {
            return nil
        }
        return pronunciation
    }
}

private struct HeadwordText: View {
    let base: String
    let pronunciation: String?

    var body: some View {
        if
            let pronunciation,
            RubyText.canSegment(base: base, reading: pronunciation)
        {
            RubyText(base: base, reading: pronunciation)
        } else if let pronunciation {
            VStack(alignment: .leading, spacing: 0) {
                Text(pronunciation)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.secondary)
                Text(base)
                    .font(.system(size: 30, weight: .semibold, design: .serif))
            }
            .textSelection(.enabled)
        } else {
            Text(base)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .textSelection(.enabled)
        }
    }
}

private struct WordDetailView: View {
    let detail: WordDetailResponse
    let related: WordRelatedGroup?
    let forvoAudio: ForvoWordAudio?
    let selectRelated: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !metadata.isEmpty || forvoAudio?.defaultPronunciation != nil {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.system(size: 14, design: .default))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let pronunciation = forvoAudio?.defaultPronunciation {
                        ForvoPlayButton(pronunciation: pronunciation)
                    }
                }
            }

            if !detail.definitionGroups.isEmpty {
                DefinitionSection(
                    groups: detail.definitionGroups,
                    selectWord: selectRelated
                )
            }

            if !detail.unassignedExampleGroups.isEmpty {
                ExampleSection(
                    title: "其他例句",
                    groups: detail.unassignedExampleGroups,
                    selectWord: selectRelated
                )
            }

            if let related, related.hasContent {
                RelatedWordsSection(
                    related: related,
                    selectRelated: selectRelated
                )
            }

            if let pronunciations = forvoAudio?.pronunciations,
               !pronunciations.isEmpty {
                ForvoPronunciationsSection(pronunciations: pronunciations)
            }
        }
    }

    private var metadata: String {
        guard let excerpt = detail.word?.excerpt, !excerpt.isEmpty else {
            return ""
        }
        return DictionaryTypography.metadataSummary(in: excerpt)
    }
}

private struct DefinitionSection: View {
    let groups: [DefinitionGroup]
    let selectWord: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            Color(nsColor: .textBackgroundColor)
                        )
                        .frame(width: 15, height: 15)
                        .background(
                            Color.secondary,
                            in: RoundedRectangle(cornerRadius: 2)
                        )
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        if let chinese = group.chinese, !chinese.isEmpty {
                            DictionaryRichText(
                                chinese,
                                pointSize: 14,
                                weight: .semibold
                            )
                                .lineSpacing(2)
                                .textSelection(.enabled)
                        }
                        if let japanese = group.japanese, !japanese.isEmpty {
                            JapaneseLookupText(
                                japanese,
                                pointSize: 14,
                                color: .secondary,
                                selectWord: selectWord
                            )
                        }

                        if !group.examples.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(group.examples) { example in
                                    ExamplePairView(
                                        group: example,
                                        selectWord: selectWord
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ExampleSection: View {
    let title: String
    let groups: [ExampleGroup]
    let selectWord: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DictionarySectionHeader(title: title)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    ExamplePairView(
                        group: group,
                        selectWord: selectWord
                    )
                }
            }
        }
    }
}

private struct ExamplePairView: View {
    let group: ExampleGroup
    let selectWord: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("▸")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                if let japanese = group.japanese, !japanese.isEmpty {
                    JapaneseLookupText(
                        japanese,
                        pointSize: 14,
                        color: .secondary,
                        selectWord: selectWord
                    )
                }
                if let chinese = group.chinese, !chinese.isEmpty {
                    DictionaryRichText(chinese, pointSize: 14)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RelatedWordsSection: View {
    let related: WordRelatedGroup
    let selectRelated: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RelatedWordGroup(
                title: "近义词",
                words: related.synonyms ?? [],
                columns: columns,
                selectRelated: selectRelated
            )
            RelatedWordGroup(
                title: "形近词",
                words: related.paronyms ?? [],
                columns: columns,
                selectRelated: selectRelated
            )
            RelatedWordGroup(
                title: "异读",
                words: related.polyphonics ?? [],
                columns: columns,
                selectRelated: selectRelated
            )

            if let subjects = related.subject, !subjects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("相关词")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(subjects) { item in
                            RelatedButton(
                                spell: item.title,
                                secondary: item.trans,
                                action: { selectRelated(item.title) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct RelatedWordGroup: View {
    let title: String
    let words: [RelatedWord]
    let columns: [GridItem]
    let selectRelated: (String) -> Void

    var body: some View {
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(words, id: \.stableID) { word in
                        RelatedButton(
                            spell: word.spell,
                            secondary: word.pron,
                            action: { selectRelated(word.spell) }
                        )
                    }
                }
            }
        }
    }
}

private struct RelatedButton: View {
    let spell: String
    let secondary: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PointerHoverLabel { isHovering in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(spell)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(.primary)
                        .underline(isHovering)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(.secondary)
                            .underline(isHovering)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ForvoPronunciationsSection: View {
    let pronunciations: [ForvoPronunciation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pronunciations) { pronunciation in
                HStack(spacing: 7) {
                    ForvoPlayButton(pronunciation: pronunciation)
                    HStack(spacing: 0) {
                        Text(pronunciation.localeDescription)
                            .foregroundStyle(.secondary)
                        if let speakerAttribution = pronunciation.speakerAttribution {
                            Text(speakerAttribution)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 12, design: .default))
                }
            }
        }
    }
}

private struct ForvoPlayButton: View {
    let pronunciation: ForvoPronunciation

    var body: some View {
        Button {
            ForvoAudioPlayer.shared.play(pronunciation)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        if let speaker = pronunciation.speaker, !speaker.isEmpty {
            return "播放 \(speaker) 在 Forvo 上传的发音"
        }
        return "播放 Forvo 发音"
    }
}

private struct DictionarySectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(.secondary)
            Divider()
        }
    }
}

private struct SearchPreviewView: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DictionaryRichText(result.excerpt, pointSize: 14)
                .lineSpacing(2)
                .textSelection(.enabled)

            Text("当前版本已经原生显示这类结果的摘要；完整结构化详情将在确认相应只读接口后接入。")
                .foregroundStyle(.secondary)

            if let url = result.webURL {
                Link(destination: url) {
                    Label(
                        "在 MOJi 网页查看完整内容",
                        systemImage: "arrow.up.right.square"
                    )
                }
            }
        }
    }
}

private struct ExternalLookupButtons: View {
    let result: SearchResult
    let headword: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                links
            }

            VStack(alignment: .leading, spacing: 8) {
                links
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private var links: some View {
        if let url = result.webURL {
            Link(destination: url) {
                Label("MOJi 官方网页", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .help("在浏览器中打开这个词的 MOJi 官方详情页")
        }

        if let url = ExternalLookupURL.systemDictionary(for: headword) {
            Link(destination: url) {
                Label("macOS 词典查询", systemImage: "character.book.closed")
            }
            .buttonStyle(.bordered)
            .help("在系统“词典”App 中查询“\(headword)”")
        }

        if let url = ForvoURL.wordPage(for: headword) {
            Link(destination: url) {
                Label("Forvo 单词页面", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .help("在浏览器中打开“\(headword)”的 Forvo 发音页面")
        }
    }
}

private struct ErrorDetailView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("载入失败", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
            Text(message)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
        }
    }
}

private struct SourceNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            Text("MOJi 在线词典 · 发音来自 Forvo 用户 · 个人只读客户端 · 与双方官方无隶属关系")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
