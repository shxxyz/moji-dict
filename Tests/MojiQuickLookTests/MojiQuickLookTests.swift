import Foundation
import XCTest
@testable import MojiQuickLook

final class MojiQuickLookTests: XCTestCase {
    func testForvoURLPercentEncodesJapaneseTerm() throws {
        let pageURL = try XCTUnwrap(ForvoURL.wordPage(for: " 踏む "))
        let requestURL = try XCTUnwrap(ForvoURL.wordRequest(for: " 踏む "))

        XCTAssertEqual(
            pageURL.absoluteString,
            "https://forvo.com/word/%E8%B8%8F%E3%82%80/#ja"
        )
        XCTAssertEqual(
            requestURL.absoluteString,
            "https://forvo.com/word/%E8%B8%8F%E3%82%80/"
        )
    }

    func testForvoLookupPrefersCanonicalDetailSpelling() {
        XCTAssertEqual(
            ForvoLookupTerm.preferred(
                detailSpell: "脇",
                fallback: "わき"
            ),
            "脇"
        )
        XCTAssertEqual(
            ForvoLookupTerm.preferred(
                detailSpell: nil,
                fallback: " 踏む "
            ),
            "踏む"
        )
    }

    func testForvoPageParserExtractsJapanesePronunciations() throws {
        let html =
            """
            <script>
            var _AUDIO_HTTP_HOST='audio12.forvo.com';
            </script>
            <li class="pronunciation li-active">
              <div class="play" id="play_1705105"
                   onclick="Play(1705105,'OTA2MTQyOC83Ni85MDYxNDI4Xzc2XzE5MzUzMTZfMS5tcDM=','',false,'YS9mL2FmXzkwNjE0MjhfNzZfMTkzNTMxNl8xLm1wMw==','','h','踏む','Japanese');return false;">
              </div>
              <span class="info">Pronunciation by
                <span data-p2="akitomo">akitomo</span>
              </span>
              <span class="responsive-gender-country">Male from Japan</span>
            </li>
            <li class="pronunciation li-active">
              <div class="play" id="play_5303168"
                   onclick="Play(5303168,'OTY5Mjc1MS83Ni85NjkyNzUxXzc2XzE5MzUzMTYubXAz','',false,'','','l','踏む','Japanese');return false;">
              </div>
              <span class="info">Pronunciation by
                <span data-p2="straycat88">straycat88</span>
              </span>
              <span class="responsive-gender-country">Female from Japan</span>
            </li>
            <li class="pronunciation li-active">
              <div class="play" id="play_6234028"
                   onclick="Play(6234028,'OTY5Mjc1MS83Ni85NjkyNzUxXzc2XzE5MzUzMTYubXAz','',false,'','','l','踏む','Japanese');return false;">
              </div>
              <span class="info">Pronunciation by
                <span class="inactive">monekuson</span>
              </span>
              <span class="responsive-gender-country">Male from Japan</span>
            </li>
            """
        let pageURL = try XCTUnwrap(ForvoURL.wordPage(for: "踏む"))
        let result = ForvoPageParser.parse(
            word: "踏む",
            pageURL: pageURL,
            html: html
        )

        XCTAssertEqual(result.pronunciations.count, 3)
        XCTAssertEqual(result.pronunciations[0].speaker, "akitomo")
        XCTAssertEqual(result.pronunciations[0].speakerHandle, "@akitomo")
        XCTAssertEqual(result.pronunciations[0].speakerAttribution, "　@akitomo")
        XCTAssertEqual(result.pronunciations[0].localeDescription, "日本・男性")
        XCTAssertEqual(
            result.pronunciations[0].audioURL.absoluteString,
            "https://audio12.forvo.com/audios/mp3/a/f/af_9061428_76_1935316_1.mp3"
        )
        XCTAssertEqual(result.pronunciations[1].speaker, "straycat88")
        XCTAssertEqual(result.pronunciations[1].speakerHandle, "@straycat88")
        XCTAssertEqual(result.pronunciations[1].speakerAttribution, "　@straycat88")
        XCTAssertEqual(result.pronunciations[1].localeDescription, "日本・女性")
        XCTAssertEqual(
            result.pronunciations[1].audioURL.absoluteString,
            "https://audio12.forvo.com/mp3/9692751/76/9692751_76_1935316.mp3"
        )
        XCTAssertEqual(result.pronunciations[2].speaker, "monekuson")
        XCTAssertEqual(result.pronunciations[2].speakerHandle, "@monekuson")
        XCTAssertEqual(result.pronunciations[2].speakerAttribution, "　@monekuson")
        XCTAssertEqual(result.pronunciations[2].localeDescription, "日本・男性")
    }

    func testJapaneseWordTokenizerPreservesTextAndMarksWords() {
        let source = "「外国の地を踏む。」"
        let runs = JapaneseWordTokenizer.runs(in: source)

        XCTAssertEqual(runs.map(\.value).joined(), source)
        XCTAssertEqual(
            runs.filter(\.isLookup).map(\.value),
            ["外国", "の", "地", "を", "踏む"]
        )
        XCTAssertFalse(runs.first?.isLookup ?? true)
        XCTAssertFalse(runs.last?.isLookup ?? true)
    }

    func testSearchResponseFlattensSectionsInDisplayOrder() throws {
        let data = Data(
            """
            {
              "word": {"list": [{"targetId":"w1","targetType":102,"title":"辞書 | じしょ ①","excerpt":"[名] 辞典"}]},
              "grammar": {"list": [{"targetId":"g1","targetType":106,"title":"ことはない","excerpt":"用不着"}]},
              "example": {"list": [{"targetId":"e1","targetType":121,"title":"国語辞書。","excerpt":"国语词典。"}]},
              "examQuestion": {"list": [{"targetId":"q1","targetType":671,"title":"試験","excerpt":"2016年7月N3","levelTag":"N3"}]}
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        XCTAssertEqual(response.flattened.map(\.category), [.word, .grammar, .example, .exam])
        XCTAssertEqual(response.flattened.first?.targetId, "w1")
        XCTAssertEqual(response.flattened.last?.levelTag, "N3")
    }

    func testWordDetailPairsBilingualDefinitionsAndExamples() throws {
        let data = Data(
            """
            {
              "word": {"id":"w1","spell":"辞書","pron":"じしょ","accent":"①","romaji":"jisho","excerpt":"[名] 辞典","tags":"N2#N5"},
              "subdetails": [
                {"id":"s1","relaId":"r1","title":"辞典","lang":"zh-CN"},
                {"id":"s2","relaId":"r1","title":"言葉を集めた書。","lang":"ja"}
              ],
              "examples": [
                {"id":"e1","relaId":"x1","subdetailsId":"r1","title":"国語辞書。","lang":"ja"},
                {"id":"e2","relaId":"x1","subdetailsId":"r1","title":"国语词典。","lang":"zh-CN"}
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WordDetailResponse.self, from: data)
        XCTAssertEqual(response.word?.tagList, ["N2", "N5"])
        XCTAssertEqual(response.word?.tagLine, "N2・N5")
        XCTAssertEqual(response.definitionGroups.first?.chinese, "辞典")
        XCTAssertEqual(response.definitionGroups.first?.japanese, "言葉を集めた書。")
        XCTAssertEqual(response.definitionGroups.first?.examples.first?.japanese, "国語辞書。")
        XCTAssertEqual(response.definitionGroups.first?.examples.first?.chinese, "国语词典。")
        XCTAssertTrue(response.unassignedExampleGroups.isEmpty)
    }

    func testWordDetailIgnoresNullExampleTranslation() throws {
        let data = Data(
            """
            {
              "word": {
                "id":"kana-word",
                "spell":"ほろ",
                "pron":"ほろ",
                "excerpt":"[副词] すこし"
              },
              "subdetails": [
                {
                  "id":"s1",
                  "relaId":"s1",
                  "title":"すこし、なんとなくなどの意を表す。",
                  "lang":"ja"
                }
              ],
              "examples": [
                {
                  "id":"e1",
                  "relaId":"pair1",
                  "subdetailsId":"s1",
                  "title":"ほろ酔い",
                  "lang":"ja"
                },
                {
                  "id":"e2",
                  "relaId":"pair1",
                  "subdetailsId":"s1",
                  "title":null,
                  "lang":"zh-CN"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WordDetailResponse.self, from: data)
        let examples = try XCTUnwrap(response.definitionGroups.first?.examples)

        XCTAssertEqual(examples.count, 1)
        XCTAssertEqual(examples.first?.japanese, "ほろ酔い")
        XCTAssertNil(examples.first?.chinese)
    }

    func testWordDetailToleratesDuplicateOrderingIDs() throws {
        let data = Data(
            """
            {
              "word": {
                "id":"198977106",
                "spell":"先々",
                "pron":"さきざき",
                "subdetailsIds":["88996","88997","88996"],
                "exampleIds":["65924","65925","65924"]
              },
              "subdetails": [
                {
                  "id":"88996",
                  "relaId":"88996",
                  "title":"将来，后日前途",
                  "lang":"zh-CN"
                },
                {
                  "id":"jp-88996",
                  "relaId":"88996",
                  "title":"遠い将来。行く末。前途。",
                  "lang":"ja"
                }
              ],
              "examples": [
                {
                  "id":"65924",
                  "relaId":"65924",
                  "subdetailsId":"88996",
                  "title":"先々が思いやられる。",
                  "lang":"ja"
                },
                {
                  "id":"zh-65924",
                  "relaId":"65924",
                  "subdetailsId":"88996",
                  "title":"前途可想而知。",
                  "lang":"zh-CN"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WordDetailResponse.self, from: data)
        let definition = try XCTUnwrap(response.definitionGroups.first)

        XCTAssertEqual(response.definitionGroups.count, 1)
        XCTAssertEqual(definition.id, "88996")
        XCTAssertEqual(definition.japanese, "遠い将来。行く末。前途。")
        XCTAssertEqual(definition.examples.count, 1)
        XCTAssertEqual(definition.examples.first?.japanese, "先々が思いやられる。")
        XCTAssertEqual(definition.examples.first?.chinese, "前途可想而知。")
    }

    func testRubySegmentationAnnotatesOnlyKanjiRuns() {
        XCTAssertEqual(
            RubySegmenter.segments(base: "踏む", reading: "ふむ"),
            [
                RubySegment(base: "踏", ruby: "ふ"),
                RubySegment(base: "む", ruby: nil)
            ]
        )
        XCTAssertEqual(
            RubySegmenter.segments(base: "取り戻す", reading: "とりもどす"),
            [
                RubySegment(base: "取", ruby: "と"),
                RubySegment(base: "り", ruby: nil),
                RubySegment(base: "戻", ruby: "もど"),
                RubySegment(base: "す", ruby: nil)
            ]
        )
        XCTAssertEqual(
            RubySegmenter.segments(base: "お祝い", reading: "おいわい"),
            [
                RubySegment(base: "お", ruby: nil),
                RubySegment(base: "祝", ruby: "いわ"),
                RubySegment(base: "い", ruby: nil)
            ]
        )
    }

    func testSidebarTitleRemovesAccentAndExcerpt() {
        let result = SearchResult(
            item: SearchItem(
                targetId: "w1",
                targetType: 102,
                title: "踏む | ふむ ⓪",
                excerpt: "不应显示",
                levelTag: "N1"
            ),
            category: .word
        )

        XCTAssertEqual(result.headword, "踏む")
        XCTAssertEqual(result.pronunciation, "ふむ")
        XCTAssertEqual(result.sidebarTitle, "踏む【ふむ】")
    }

    func testLookupHistoryMovesAndDropsForwardBranch() {
        let first = LookupPage(
            query: "踏む",
            filter: .word,
            selectedID: "word-102-w1"
        )
        let second = LookupPage(
            query: "辞書",
            filter: .word,
            selectedID: "word-102-w2"
        )
        let branch = LookupPage(
            query: "注ぐ",
            filter: .word,
            selectedID: "word-102-w3"
        )
        var history = LookupHistory()

        history.record(first)
        history.record(second)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertTrue(history.canGoForward)

        history.record(branch)
        XCTAssertEqual(history.pages, [first, branch])
        XCTAssertFalse(history.canGoForward)
    }

    func testSystemDictionaryURLPercentEncodesJapaneseTerm() throws {
        let url = try XCTUnwrap(
            ExternalLookupURL.systemDictionary(for: " 踏む ")
        )

        XCTAssertEqual(
            url.absoluteString,
            "dict://%E8%B8%8F%E3%82%80"
        )
    }

    func testSearchURLPreservesRepeatedTypeParameters() throws {
        let url = try MojiAPIClient.searchURL(for: "辞書")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let typeValues = components.queryItems?
            .filter { $0.name == "types" }
            .compactMap(\.value)

        XCTAssertEqual(typeValues, ["102", "106", "103", "671"])
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "text" })?.value,
            "辞書"
        )
    }

    func testEmailLoginRequestMatchesCapturedProtocol() throws {
        let request = try MojiAPIClient.loginRequest(
            email: "reader@example.com",
            password: "test-password",
            deviceID: "test-device-id"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let payload = try XCTUnwrap(json["authPayload"] as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(json["authName"] as? String, "PasswordAuth")
        XCTAssertEqual(payload["email"] as? String, "reader@example.com")
        XCTAssertEqual(payload["code"] as? String, "test-password")
        XCTAssertNil(payload["password"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MOJI-OS"), "PCWeb")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-MOJI-APP-ID"),
            "com.mojitec.mojidict"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-MOJI-DEVICE-ID"),
            "test-device-id"
        )
    }

    func testRelatedWordRequestMatchesWebProtocol() throws {
        let request = try MojiAPIClient.wordRelatedRequest(
            id: "19894628",
            deviceID: "test-device-id"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(json["wordIds"] as? [String], ["19894628"])
    }

    func testRelatedSubjectsWithSameWordIDHaveDistinctViewIdentity() {
        let lookingBack = RelatedSubject(
            title: "振り返る",
            trans: "回头看",
            relatedId: "198971081",
            relateId: "zTPM4MAUD4"
        )
        let reflecting = RelatedSubject(
            title: "振り返る",
            trans: "回顾",
            relatedId: "198971081",
            relateId: "zTPM4MAUD4"
        )

        XCTAssertNotEqual(lookingBack.id, reflecting.id)
    }

    func testLoginResponseDecodesCapturedShape() throws {
        let data = Data(
            """
            {
              "sessionToken": "session",
              "user": {
                "objectId": "user",
                "name": "Reader",
                "email": "reader@example.com"
              },
              "isNew": false,
              "needBindMobile": false
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        XCTAssertEqual(response.sessionToken, "session")
        XCTAssertEqual(response.user.name, "Reader")
        XCTAssertEqual(response.user.email, "reader@example.com")
        XCTAssertFalse(response.isNew ?? true)
    }

    func testPersistedAccountSessionRoundTrips() throws {
        let original = PersistedAccountSession(
            sessionToken: "session-token",
            deviceID: "device-id",
            displayName: "Reader",
            email: "reader@example.com"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedAccountSession.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDictionaryTypographyCompactsCJKPunctuationSpacing() {
        XCTAssertEqual(
            DictionaryTypography.compactedPunctuation(
                in: "踏 ，　踩， 践踏 ；　跺脚： 走上"
            ),
            "踏，踩，践踏；跺脚：走上"
        )
        XCTAssertEqual(
            DictionaryTypography.parts(in: "[名][五段] 辞典"),
            [
                DictionaryTextPart(value: "[名]", isMetadata: true),
                DictionaryTextPart(value: "[五段]", isMetadata: true),
                DictionaryTextPart(value: " 辞典", isMetadata: false)
            ]
        )
        XCTAssertEqual(
            DictionaryTypography.metadataSummary(
                in: "[他动・五段] 踩；实践；经历"
            ),
            "[他动・五段]"
        )
    }

    func testLiveSearchAndWordDetailWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set MOJI_LIVE_TESTS=1 to run the read-only live endpoint test.")
        }

        let client = MojiAPIClient()
        let search = try await client.search("踏む")
        let firstWord = try XCTUnwrap(search.word?.list?.first)
        XCTAssertEqual(firstWord.targetType, 102)

        let detail = try await client.wordDetail(id: firstWord.targetId)
        XCTAssertFalse(detail.word?.spell?.isEmpty ?? true)
        XCTAssertFalse(detail.definitionGroups.isEmpty)
        XCTAssertFalse(detail.definitionGroups.first?.examples.isEmpty ?? true)

        let related = try await client.wordRelated(id: firstWord.targetId)
        XCTAssertTrue(related?.hasContent ?? false)

        for query in ["ほろ", "全く"] {
            let response = try await client.search(query)
            let secondWord = try XCTUnwrap(response.word?.list?.dropFirst().first)
            let detail = try await client.wordDetail(id: secondWord.targetId)
            XCTAssertFalse(detail.word?.spell?.isEmpty ?? true)
            XCTAssertFalse(detail.definitionGroups.isEmpty)
        }

        let sakisakiSearch = try await client.search("先々")
        let sakisakiWord = try XCTUnwrap(sakisakiSearch.word?.list?.first)
        let sakisakiDetail = try await client.wordDetail(id: sakisakiWord.targetId)
        XCTAssertEqual(sakisakiDetail.word?.spell, "先々")
        XCTAssertFalse(sakisakiDetail.definitionGroups.isEmpty)
        _ = sakisakiDetail.unassignedExampleGroups
    }

    func testLiveForvoWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set MOJI_LIVE_TESTS=1 to run the read-only live endpoint test.")
        }

        let client = ForvoClient()
        let result = try await client.pronunciations(for: "踏む")
        let first = try XCTUnwrap(result.pronunciations.first)

        XCTAssertTrue(first.audioURL.host()?.hasSuffix(".forvo.com") ?? false)
        XCTAssertEqual(first.audioURL.pathExtension, "mp3")
        XCTAssertFalse(first.speaker?.isEmpty ?? true)
        XCTAssertFalse(first.profile?.isEmpty ?? true)
        XCTAssertFalse(first.localeDescription.isEmpty)

        let (audioData, response) = try await URLSession.shared.data(
            from: first.audioURL
        )
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertTrue(
            httpResponse.value(forHTTPHeaderField: "Content-Type")?
                .hasPrefix("audio/") ?? false
        )
        XCTAssertGreaterThan(audioData.count, 1_000)

        _ = try? await client.pronunciations(for: "わき")
        let waki = try await client.pronunciations(for: "脇")
        XCTAssertFalse(waki.pronunciations.isEmpty)
        XCTAssertTrue(
            waki.pronunciations.contains {
                $0.localeDescription == "日本・女性"
            }
        )
    }

    func testLiveWakiViewModelWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set MOJI_LIVE_TESTS=1 to run the read-only live endpoint test.")
        }

        let model = await SearchViewModel()
        await MainActor.run {
            model.query = "脇"
            model.searchImmediately()
        }

        for _ in 0..<40 {
            let isFinished = await MainActor.run {
                model.forvoAudio != nil || model.searchError != nil
            }
            if isFinished { break }
            try await Task.sleep(for: .milliseconds(200))
        }

        let initialCount = await MainActor.run {
            model.forvoAudio?.pronunciations.count ?? 0
        }
        XCTAssertGreaterThan(initialCount, 0)

        await MainActor.run {
            model.query = "わき"
            model.searchImmediately()
        }

        for _ in 0..<40 {
            let isFinished = await MainActor.run {
                model.forvoAudio != nil || model.searchError != nil
            }
            if isFinished { break }
            try await Task.sleep(for: .milliseconds(200))
        }

        let snapshot = await MainActor.run {
            (
                resultHeadword: model.selectedResult?.headword,
                detailSpell: model.detail?.word?.spell,
                pronunciationCount: model.forvoAudio?.pronunciations.count,
                searchError: model.searchError,
                detailError: model.detailError
            )
        }
        XCTAssertEqual(snapshot.resultHeadword, "わき")
        XCTAssertEqual(snapshot.detailSpell, "脇")
        XCTAssertNil(snapshot.searchError)
        XCTAssertNil(snapshot.detailError)
        XCTAssertGreaterThan(snapshot.pronunciationCount ?? 0, 0)
    }
}
