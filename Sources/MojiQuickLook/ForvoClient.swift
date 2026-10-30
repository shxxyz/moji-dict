import Foundation

enum ForvoURL {
    static func wordPage(for term: String) -> URL? {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        guard
            let encoded = normalized.addingPercentEncoding(
                withAllowedCharacters: allowed
            )
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "forvo.com"
        components.percentEncodedPath = "/word/\(encoded)/"
        components.fragment = "ja"
        return components.url
    }

    static func wordRequest(for term: String) -> URL? {
        guard
            let pageURL = wordPage(for: term),
            var components = URLComponents(
                url: pageURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }
        components.fragment = nil
        return components.url
    }
}

enum ForvoLookupTerm {
    static func preferred(
        detailSpell: String?,
        fallback: String
    ) -> String {
        let detailSpell = detailSpell?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let detailSpell, !detailSpell.isEmpty {
            return detailSpell
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ForvoPronunciation: Identifiable, Hashable, Sendable {
    let id: String
    let audioURL: URL
    let speaker: String?
    let profile: String?

    var speakerHandle: String? {
        guard
            let speaker = speaker?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            !speaker.isEmpty
        else {
            return nil
        }
        return speaker.hasPrefix("@") ? speaker : "@\(speaker)"
    }

    var speakerAttribution: String? {
        speakerHandle.map { "　\($0)" }
    }

    var localeDescription: String {
        guard let profile, !profile.isEmpty else {
            return speaker ?? "Forvo"
        }

        let values: (gender: String, country: String)?
        if profile.hasPrefix("Male from ") {
            values = ("男性", String(profile.dropFirst("Male from ".count)))
        } else if profile.hasPrefix("Female from ") {
            values = ("女性", String(profile.dropFirst("Female from ".count)))
        } else {
            values = nil
        }

        guard let values else { return profile }
        return "\(Self.localizedCountry(values.country))・\(values.gender)"
    }

    private static func localizedCountry(_ value: String) -> String {
        switch value {
        case "Japan": "日本"
        case "China": "中国"
        case "Taiwan": "台湾"
        case "South Korea": "韩国"
        case "United States": "美国"
        case "United Kingdom": "英国"
        case "Canada": "加拿大"
        case "Australia": "澳大利亚"
        case "France": "法国"
        case "Germany": "德国"
        default: value
        }
    }
}

struct ForvoWordAudio: Equatable, Sendable {
    let word: String
    let pageURL: URL
    let pronunciations: [ForvoPronunciation]

    var defaultPronunciation: ForvoPronunciation? {
        pronunciations.first
    }
}

enum ForvoClientError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "无法构造 Forvo 单词页面地址。"
        case .invalidResponse:
            "Forvo 返回了无法识别的页面。"
        case let .httpStatus(code):
            "Forvo 返回 HTTP \(code)。"
        }
    }
}

actor ForvoClient {
    static let shared = ForvoClient()

    private let session: URLSession
    private var cache: [String: ForvoWordAudio] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            configuration.httpAdditionalHeaders = [
                "Accept": "text/html,application/xhtml+xml",
                "Accept-Language": "ja,en;q=0.8",
                "User-Agent": "Moji-Dictionary/0.15.1 (macOS; personal non-commercial client)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func pronunciations(
        for word: String,
        forceRefresh: Bool = false
    ) async throws -> ForvoWordAudio {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let pageURL = ForvoURL.wordPage(for: normalized),
            let requestURL = ForvoURL.wordRequest(for: normalized)
        else {
            throw ForvoClientError.invalidURL
        }

        if !forceRefresh, let cached = cache[normalized] {
            return cached
        }

        let (data, response) = try await session.data(from: requestURL)
        guard let response = response as? HTTPURLResponse else {
            throw ForvoClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForvoClientError.httpStatus(response.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ForvoClientError.invalidResponse
        }

        let result = ForvoPageParser.parse(
            word: normalized,
            pageURL: pageURL,
            html: html
        )
        cache[normalized] = result
        return result
    }

    func clearMemoryCache() {
        cache.removeAll()
    }
}

enum ForvoPageParser {
    static func parse(
        word: String,
        pageURL: URL,
        html: String
    ) -> ForvoWordAudio {
        guard
            let audioHost = firstCapture(
                #"_AUDIO_HTTP_HOST\s*=\s*['\"]([^'\"]+)['\"]"#,
                in: html
            ),
            audioHost == "forvo.com" || audioHost.hasSuffix(".forvo.com")
        else {
            return ForvoWordAudio(
                word: word,
                pageURL: pageURL,
                pronunciations: []
            )
        }

        let blocks = captures(
            #"<li\b[^>]*class=['\"][^'\"]*\bpronunciation\b[^'\"]*['\"][^>]*>(.*?)</li>"#,
            in: html
        )
        let pronunciations: [ForvoPronunciation] = blocks.compactMap { values in
            guard values.count > 1 else { return nil }
            return pronunciation(from: values[1], audioHost: audioHost)
        }

        return ForvoWordAudio(
            word: word,
            pageURL: pageURL,
            pronunciations: pronunciations
        )
    }

    private static func pronunciation(
        from block: String,
        audioHost: String
    ) -> ForvoPronunciation? {
        guard
            let rawArguments = firstCapture(#"Play\((.*?)\)"#, in: block)
        else {
            return nil
        }

        let arguments = javascriptArguments(in: rawArguments)
        guard
            arguments.count >= 9,
            arguments[8] == "Japanese",
            !arguments[0].isEmpty
        else {
            return nil
        }

        let prefersHighQuality = arguments[6] == "h"
        let encodedPath: String
        let directory: String
        if prefersHighQuality, !arguments[4].isEmpty {
            encodedPath = arguments[4]
            directory = "audios/mp3"
        } else {
            encodedPath = arguments[1]
            directory = "mp3"
        }

        guard
            let pathData = Data(
                base64Encoded: encodedPath,
                options: .ignoreUnknownCharacters
            ),
            let path = String(data: pathData, encoding: .utf8),
            isSafeMP3Path(path),
            let audioURL = URL(
                string: "https://\(audioHost)/\(directory)/\(path)"
            )
        else {
            return nil
        }

        let speaker = firstCapture(
            #"Pronunciation\s+by(?:\s|&nbsp;)*<span[^>]*data-p2=['\"]([^'\"]+)['\"]"#,
            in: block
        ).map(decodeHTMLEntities) ?? firstCapture(
            #"Pronunciation\s+by(?:\s|&nbsp;)*<span[^>]*>(.*?)</span>"#,
            in: block
        ).map {
            decodeHTMLEntities(strippingTags(from: $0))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let profile = firstCapture(
            #"class=['\"]responsive-gender-country['\"][^>]*>(.*?)</span>"#,
            in: block
        ).map { decodeHTMLEntities(strippingTags(from: $0)) }

        return ForvoPronunciation(
            id: arguments[0],
            audioURL: audioURL,
            speaker: speaker,
            profile: profile
        )
    }

    private static func javascriptArguments(in value: String) -> [String] {
        var output: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\", isQuoted {
                isEscaped = true
            } else if character == "'" {
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return output
    }

    private static func isSafeMP3Path(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("/")
            && value.lowercased().hasSuffix(".mp3")
            && !value.contains("..")
            && !value.contains("://")
    }

    private static func strippingTags(from value: String) -> String {
        value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(
        _ pattern: String,
        in value: String
    ) -> String? {
        captures(pattern, in: value).first.flatMap { values in
            values.count > 1 ? values[1] : nil
        }
    }

    private static func captures(
        _ pattern: String,
        in value: String
    ) -> [[String]] {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else {
            return []
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let captureRange = match.range(at: index)
                guard
                    captureRange.location != NSNotFound,
                    let range = Range(captureRange, in: value)
                else {
                    return ""
                }
                return String(value[range])
            }
        }
    }
}
