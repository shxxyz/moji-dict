import Foundation

enum SearchCategory: String, CaseIterable, Identifiable, Sendable {
    case word
    case grammar
    case example
    case exam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: "词条"
        case .grammar: "文法"
        case .example: "例句"
        case .exam: "真题"
        }
    }

    var symbolName: String {
        switch self {
        case .word: "character.book.closed"
        case .grammar: "text.book.closed"
        case .example: "quote.bubble"
        case .exam: "checkmark.seal"
        }
    }
}

enum ResultFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case word
    case grammar
    case example
    case exam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .word: "词条"
        case .grammar: "文法"
        case .example: "例句"
        case .exam: "真题"
        }
    }

    var category: SearchCategory? {
        switch self {
        case .all: nil
        case .word: .word
        case .grammar: .grammar
        case .example: .example
        case .exam: .exam
        }
    }
}

struct SearchResponse: Decodable, Sendable {
    let word: SearchSection?
    let grammar: SearchSection?
    let example: SearchSection?
    let examQuestion: SearchSection?

    var flattened: [SearchResult] {
        var output: [SearchResult] = []
        output.append(contentsOf: (word?.list ?? []).map { SearchResult(item: $0, category: .word) })
        output.append(contentsOf: (grammar?.list ?? []).map { SearchResult(item: $0, category: .grammar) })
        output.append(contentsOf: (example?.list ?? []).map { SearchResult(item: $0, category: .example) })
        output.append(contentsOf: (examQuestion?.list ?? []).map { SearchResult(item: $0, category: .exam) })
        return output
    }
}

struct LoginResponse: Decodable, Sendable {
    let sessionToken: String
    let user: LoginUser
    let isNew: Bool?
    let needBindMobile: Bool?
}

struct LoginUser: Decodable, Sendable {
    let objectId: String?
    let name: String?
    let email: String?
}

struct SearchSection: Decodable, Sendable {
    let list: [SearchItem]?
}

struct SearchItem: Decodable, Sendable {
    let targetId: String
    let targetType: Int
    let title: String
    let excerpt: String?
    let levelTag: String?
}

struct SearchResult: Identifiable, Hashable, Sendable {
    let targetId: String
    let targetType: Int
    let title: String
    let excerpt: String
    let levelTag: String?
    let category: SearchCategory

    init(item: SearchItem, category: SearchCategory) {
        targetId = item.targetId
        targetType = item.targetType
        title = item.title
        excerpt = item.excerpt ?? ""
        levelTag = item.levelTag
        self.category = category
    }

    var id: String {
        "\(category.rawValue)-\(targetType)-\(targetId)"
    }

    var webURL: URL? {
        URL(string: "https://www.mojidict.com/details/\(targetId)")
    }

    var headword: String {
        titleParts.first ?? title
    }

    var pronunciation: String? {
        guard titleParts.count > 1 else { return nil }
        let reading = titleParts[1]
            .unicodeScalars
            .filter { !$0.isAccentSymbol }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reading.isEmpty ? nil : reading
    }

    var sidebarTitle: String {
        guard let pronunciation, pronunciation != headword else {
            return headword
        }
        return "\(headword)【\(pronunciation)】"
    }

    private var titleParts: [String] {
        title
            .split(separator: "|", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum ExternalLookupURL {
    static func systemDictionary(for term: String) -> URL? {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        guard
            let encoded = normalized.addingPercentEncoding(
                withAllowedCharacters: allowed
            )
        else {
            return nil
        }
        return URL(string: "dict://\(encoded)")
    }
}

struct WordDetailResponse: Decodable, Sendable {
    let word: WordInfo?
    let subdetails: [Subdetail]?
    let examples: [WordExample]?
    let custo: WordCustomization?

    var definitionGroups: [DefinitionGroup] {
        let items = subdetails ?? []
        let chinese = items.filter { $0.lang == "zh-CN" }
        let japanese = items.filter { $0.lang == "ja" }
        let exampleItems = examples ?? []

        var groups = chinese.map { item in
            let identifiers = Set([item.id, item.relaId].compactMap { $0 })
            return DefinitionGroup(
                id: item.relaId,
                chinese: item.title,
                japanese: japanese.first(where: { $0.relaId == item.relaId })?.title,
                examples: Self.pairExamples(
                    exampleItems.filter { example in
                        example.subdetailsId.map(identifiers.contains) ?? false
                    },
                    order: exampleOrder
                )
            )
        }

        for item in japanese where !groups.contains(where: { $0.id == item.relaId }) {
            let identifiers = Set([item.id, item.relaId].compactMap { $0 })
            groups.append(
                DefinitionGroup(
                    id: item.relaId,
                    chinese: nil,
                    japanese: item.title,
                    examples: Self.pairExamples(
                        exampleItems.filter { example in
                            example.subdetailsId.map(identifiers.contains) ?? false
                        },
                        order: exampleOrder
                    )
                )
            )
        }

        let order = definitionOrder
        return groups.sorted {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    var unassignedExampleGroups: [ExampleGroup] {
        let definitionIDs = Set(
            (subdetails ?? []).flatMap { [$0.id, $0.relaId].compactMap { $0 } }
        )
        let items = (examples ?? []).filter { example in
            guard let subdetailsId = example.subdetailsId else { return true }
            return !definitionIDs.contains(subdetailsId)
        }
        return Self.pairExamples(items, order: exampleOrder)
    }

    private var definitionOrder: [String: Int] {
        let ids = custo?.subdetailsIds ?? word?.subdetailsIds ?? []
        return Self.firstOccurrenceOrder(in: ids)
    }

    private var exampleOrder: [String: Int] {
        let ids = custo?.exampleIds ?? word?.exampleIds ?? []
        return Self.firstOccurrenceOrder(in: ids)
    }

    private static func firstOccurrenceOrder(
        in identifiers: [String]
    ) -> [String: Int] {
        var order: [String: Int] = [:]
        for (offset, identifier) in identifiers.enumerated()
        where order[identifier] == nil {
            order[identifier] = offset
        }
        return order
    }

    private static func pairExamples(
        _ items: [WordExample],
        order: [String: Int]
    ) -> [ExampleGroup] {
        let japanese = items.filter {
            $0.lang == "ja" && $0.displayTitle != nil
        }
        let chinese = items.filter {
            $0.lang == "zh-CN" && $0.displayTitle != nil
        }

        var groups = japanese.map { item in
            ExampleGroup(
                id: item.relaId,
                japanese: item.displayTitle,
                chinese: chinese.first(where: {
                    $0.relaId == item.relaId
                })?.displayTitle
            )
        }

        for item in chinese where !groups.contains(where: { $0.id == item.relaId }) {
            groups.append(
                ExampleGroup(
                    id: item.relaId,
                    japanese: nil,
                    chinese: item.displayTitle
                )
            )
        }
        return groups.sorted {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }
}

struct WordInfo: Decodable, Sendable {
    let id: String?
    let spell: String?
    let pron: String?
    let accent: String?
    let romaji: String?
    let romajiHepburn: String?
    let excerpt: String?
    let tags: String?
    let subdetailsIds: [String]?
    let exampleIds: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case spell
        case pron
        case accent
        case romaji
        case romajiHepburn = "romaji_hepburn"
        case excerpt
        case tags
        case subdetailsIds
        case exampleIds
    }

    var displayRomaji: String? {
        if let romajiHepburn, !romajiHepburn.isEmpty {
            return romajiHepburn
        }
        return romaji
    }

    var tagList: [String] {
        (tags ?? "")
            .split(separator: "#")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var tagLine: String {
        tagList.joined(separator: "・")
    }
}

struct WordCustomization: Decodable, Sendable {
    let subdetailsIds: [String]?
    let exampleIds: [String]?
}

struct Subdetail: Decodable, Sendable {
    let id: String
    let relaId: String
    let title: String
    let lang: String
}

struct WordExample: Decodable, Sendable {
    let id: String
    let relaId: String
    let subdetailsId: String?
    let title: String?
    let lang: String

    var displayTitle: String? {
        guard
            let title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return title
    }
}

struct DefinitionGroup: Identifiable, Hashable, Sendable {
    let id: String
    let chinese: String?
    let japanese: String?
    let examples: [ExampleGroup]
}

struct ExampleGroup: Identifiable, Hashable, Sendable {
    let id: String
    let japanese: String?
    let chinese: String?
}

struct WordRelatedResponse: Decodable, Sendable {
    let list: [WordRelatedGroup]?

    var first: WordRelatedGroup? {
        list?.first
    }
}

struct WordRelatedGroup: Decodable, Sendable {
    let synonyms: [RelatedWord]?
    let paronyms: [RelatedWord]?
    let polyphonics: [RelatedWord]?
    let subject: [RelatedSubject]?

    var hasContent: Bool {
        !(synonyms ?? []).isEmpty
            || !(paronyms ?? []).isEmpty
            || !(polyphonics ?? []).isEmpty
            || !(subject ?? []).isEmpty
    }
}

struct RelatedWord: Decodable, Hashable, Sendable {
    let id: String?
    let objectId: String?
    let spell: String
    let pron: String?

    var stableID: String {
        id ?? objectId ?? "\(spell)-\(pron ?? "")"
    }
}

struct RelatedSubject: Decodable, Identifiable, Hashable, Sendable {
    let title: String
    let trans: String?
    let relatedId: String?
    let relateId: String?

    var id: String {
        [
            relatedId ?? "",
            relateId ?? "",
            title,
            trans ?? ""
        ]
        .joined(separator: "\u{1F}")
    }
}

private extension Unicode.Scalar {
    var isAccentSymbol: Bool {
        switch value {
        case 0x2460...0x2473, 0x24EA, 0x3251...0x325F, 0x32B1...0x32BF:
            true
        default:
            false
        }
    }
}
