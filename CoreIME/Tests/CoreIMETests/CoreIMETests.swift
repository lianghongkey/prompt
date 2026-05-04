import XCTest
@testable import CoreIME

final class CoreIMETests: XCTestCase {

        // MARK: - Segmentor (full pinyin, regression)

        func testPinyinSegmentor() throws {
                let text: String = "putonghuapinyin"
                let schemes: Segmentation = PinyinSegmentor.segment(text: text)
                if let scheme = schemes.first {
                        let syllables = scheme.map(\.text)
                        XCTAssertEqual(syllables, ["pu", "tong", "hua", "pin", "yin"])
                        XCTAssertTrue(scheme.isAllFull)
                } else {
                        XCTFail("No schemes")
                }
        }

        func testGengaoxiaoSegmentation() throws {
                let text = "gengaoxiao"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                // Best scheme is 3 full tokens (no abbrev). Both gen+gao+xiao and
                // geng+ao+xiao tie on (count, abbrevCount); both should appear among
                // top-quality schemes.
                XCTAssertEqual(best.count, 3)
                XCTAssertEqual(best.abbrevCount, 0)
                let topQualitySchemes = schemes.filter { $0.count == best.count && $0.abbrevCount == best.abbrevCount }
                let topTexts = topQualitySchemes.map { $0.map(\.text) }
                XCTAssertTrue(topTexts.contains(["gen", "gao", "xiao"]), "got top: \(topTexts)")
                XCTAssertTrue(topTexts.contains(["geng", "ao", "xiao"]), "got top: \(topTexts)")
        }

        func testGengaoxiaoSuggest() throws {
                Engine.prepare()
                let text = "gengaoxiao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let texts = candidates.map(\.text)
                XCTAssertTrue(texts.contains("根高"), "gen+gao should surface 根高")
                XCTAssertTrue(texts.contains("更傲"), "geng+ao should surface 更傲")
        }

        func testZhidaoOrdering() throws {
                Engine.prepare()
                let text = "zhidao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                guard let top = candidates.first else { XCTFail("no candidates"); return }
                XCTAssertEqual(top.text, "知道", "top candidate for zhidao should be 知道")
                XCTAssertEqual(top.input, "zhidao")
        }

        // MARK: - Max Syllable Count

        func testMaxSyllableCountBaseline() throws {
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: ""), 0)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "l"), 1, "single initial → 1 abbrev token")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lh"), 2, "two initials → 2 abbrev tokens")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "li"), 1)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lian"), 1)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liang"), 1)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lianh"), 2, "lian + h abbrev")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liangh"), 2, "liang + h abbrev")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "ni"), 1)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "nh"), 2)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "nihao"), 2, "ni + hao")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zh"), 1, "zh is a 2-letter abbrev")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zhi"), 1)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zhih"), 2, "zhi + h abbrev")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "a"), 1, "zero-initial full syllable")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "an"), 1, "an is a full syllable")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "anh"), 2, "an full + h abbrev")
        }

        /// "ho" is not a real syllable, so the new model splits it into
        /// `[h(abbrev), o(zero-initial-full)]`. Total tokens = 3 for "liangho".
        /// (The old heuristic counted "ho" as one partial syllable, returning 2.
        /// The new behavior is more semantically correct: 'o' is its own syllable.)
        func testMaxSyllableCountLianghoIsThree() throws {
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liangho"), 3, "liang + h + o = 3")
        }

        // MARK: - Hybrid (initials + full syllable mix)

        /// Core regression for the original bug: "zmyan" must produce 怎么样.
        /// `zm` are abbrev initials, `yan` is a full syllable that prefix-matches
        /// the canonical syllable `yang` (since "yan" is a prefix of "yang").
        func testZmyanProduces怎么样() throws {
                Engine.prepare()
                let text = "zmyan"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["z", "m", "yan"])
                XCTAssertEqual(best.map(\.kind), [.abbrev, .abbrev, .full])

                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "怎么样" }),
                              "zmyan should produce 怎么样; top: \(candidates.prefix(5).map(\.text))")
        }

        func testZmyangProduces怎么样() throws {
                Engine.prepare()
                let text = "zmyang"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["z", "m", "yang"])
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "怎么样" }),
                              "zmyang should produce 怎么样; top: \(candidates.prefix(5).map(\.text))")
        }

        /// Pure-initials shortcut still works: "zmy" picks scheme [z,m,y].
        func testZmyShortcutStillWorks() throws {
                Engine.prepare()
                let text = "zmy"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["z", "m", "y"])
                XCTAssertTrue(best.allSatisfy { $0.kind == .abbrev })
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "怎么样" }),
                              "zmy should produce 怎么样; top: \(candidates.prefix(5).map(\.text))")
        }

        /// "wsmyao" = w(abbrev) + s(abbrev) + m(abbrev) + yao(full). Should produce
        /// 为什么要 (wei shen me yao).
        func testWsmyaoProduces为什么要() throws {
                Engine.prepare()
                let text = "wsmyao"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["w", "s", "m", "yao"])
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "为什么要" }),
                              "wsmyao should produce 为什么要; top: \(candidates.prefix(10).map(\.text))")
        }

        /// "nhao" = n(abbrev) + hao(full). Should produce 你好.
        func testNhaoProduces你好() throws {
                Engine.prepare()
                let text = "nhao"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["n", "hao"])
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "你好" }),
                              "nhao should produce 你好; top: \(candidates.prefix(5).map(\.text))")
        }

        // MARK: - Token kind invariants

        /// `a/o/e` are zero-initial full syllables, NEVER abbrevs.
        func testZeroInitialIsFullNotAbbrev() throws {
                for s in ["a", "o", "e", "an", "ao", "en", "ang", "eng", "ng"] {
                        let schemes = PinyinSegmentor.segment(text: s)
                        guard let scheme = schemes.first else { XCTFail("no scheme for \(s)"); continue }
                        XCTAssertEqual(scheme.first?.kind, .full, "\(s) first token must be full")
                }
        }

        /// 1- and 2-letter pure initials are abbrevs.
        func testInitialsAreAbbrev() throws {
                for s in ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                          "j", "q", "x", "r", "z", "c", "s", "y", "w",
                          "zh", "ch", "sh"] {
                        let schemes = PinyinSegmentor.segment(text: s)
                        guard let scheme = schemes.first else { XCTFail("no scheme for \(s)"); continue }
                        XCTAssertEqual(scheme.count, 1, "\(s) should be 1 token")
                        XCTAssertEqual(scheme.first?.kind, .abbrev, "\(s) should be abbrev")
                }
        }

        // MARK: - Trailing nasal does not inflate token count

        func testZmyangIsThreeTokensNotFive() throws {
                let schemes = PinyinSegmentor.segment(text: "zmyang")
                guard let best = schemes.first else { XCTFail(); return }
                XCTAssertEqual(best.count, 3, "zmyang must be [z,m,yang] not [z,m,y,a,ng]")
        }

        func testZmyanIsThreeTokensNotFour() throws {
                let schemes = PinyinSegmentor.segment(text: "zmyan")
                guard let best = schemes.first else { XCTFail(); return }
                XCTAssertEqual(best.count, 3, "zmyan must be [z,m,yan] not [z,m,y,an]")
        }

        // MARK: - Partial / mid-typing input

        func testPartialZmyaIsThreeTokens() throws {
                // "zmya": z(abbrev) + m(abbrev) + ya(full). 3 tokens, 2 abbrev.
                let schemes = PinyinSegmentor.segment(text: "zmya")
                guard let best = schemes.first else { XCTFail(); return }
                XCTAssertEqual(best.count, 3)
                XCTAssertEqual(best.abbrevCount, 2)
                XCTAssertEqual(best.map(\.text), ["z", "m", "ya"])
        }

        // MARK: - Single-char fallback (word creation)

        /// When user types "zhidao" and selects 知 (single char), they should be
        /// able to enter word creation. The candidate list must include both 知道
        /// (full match) and 知 (single-char fallback for word creation).
        func testZhidaoHasSingleCharFallback() throws {
                Engine.prepare()
                let text = "zhidao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "知道" }))
                XCTAssertTrue(candidates.contains(where: { $0.text == "知" }))
        }

        // MARK: - Full-pinyin typo / partial typing

        /// User typed "zenmeyan" intending 怎么样 (yang). The all-full ping path
        /// finds nothing exact, but the prefix-match fallback should surface 怎么样
        /// because "yan" is a prefix of "yang".
        func testZenmeyanFallsBackToPrefix() throws {
                Engine.prepare()
                let text = "zenmeyan"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail(); return }
                XCTAssertTrue(best.isAllFull, "zenmeyan should segment as all-full [zen, me, yan]")
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertTrue(candidates.contains(where: { $0.text == "怎么样" }),
                              "zenmeyan should still surface 怎么样; top: \(candidates.prefix(5).map(\.text))")
        }

        /// "zenme" exact match must rank 怎么 first, not get drowned out by
        /// prefix-extension candidates from 怎门, 增没 etc. Ping path runs first
        /// and exits before prefix backfill.
        func testZenmeExactFirst() throws {
                Engine.prepare()
                let text = "zenme"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                guard let top = candidates.first else { XCTFail("no candidates"); return }
                XCTAssertEqual(top.text, "怎么", "top of zenme should be 怎么; got \(candidates.prefix(5).map(\.text))")
        }

        // MARK: - Single-letter syllables

        /// Only `a`, `e`, `o` are single-letter full syllables. Anything else
        /// single-letter must be abbrev (or unsegmentable).
        func testSingleLetterSyllableSet() throws {
                for s in ["a", "e", "o"] {
                        let scheme = PinyinSegmentor.segment(text: s).first
                        XCTAssertEqual(scheme?.first?.kind, .full, "\(s) should be full")
                }
                for s in ["b", "n", "z", "y"] {
                        let scheme = PinyinSegmentor.segment(text: s).first
                        XCTAssertEqual(scheme?.first?.kind, .abbrev, "\(s) should be abbrev")
                }
                // 'i', 'u', 'v' are neither valid abbrev nor full syllables.
                XCTAssertEqual(PinyinSegmentor.segment(text: "i").count, 0)
                XCTAssertEqual(PinyinSegmentor.segment(text: "u").count, 0)
        }

        // MARK: - 'ng' is a full syllable

        func testNgIsOneToken() throws {
                let scheme = PinyinSegmentor.segment(text: "ng").first
                XCTAssertEqual(scheme?.count, 1)
                XCTAssertEqual(scheme?.first?.kind, .full)
                XCTAssertEqual(scheme?.first?.text, "ng")
        }

        /// Regression: when an all-full scheme's `ping` query matches rows that the
        /// caller already had (e.g. UserLexicon's directPingMatches priming), the
        /// runScheme early-return must still fire — otherwise the noisy shortcut+
        /// prefix fallback runs and surfaces unrelated longer words like 形成
        /// (xing cheng) for input "xiche". Test the Engine half here; the
        /// UserLexicon half is exercised in the app.
        func testXicheAllFullDoesNotLeakLongerPrefix() throws {
                Engine.prepare()
                let text = "xiche"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertFalse(candidates.contains(where: { $0.text == "形成" }),
                               "xiche must not surface 形成 (xing cheng); got top: \(candidates.prefix(10).map(\.text))")
        }

        /// Mirror of testXicheAllFullDoesNotLeakLongerPrefix: when "zhe kuai" has
        /// exact ping matches (这块/这快...), the shortcut+prefix path must NOT
        /// fall through and surface 整块 (zheng kuai) via "zhe prefix-of zheng".
        func testZhekuaiAllFullDoesNotLeakLongerPrefix() throws {
                Engine.prepare()
                let text = "zhekuai"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let topTexts = candidates.prefix(15).map(\.text)
                XCTAssertFalse(candidates.contains(where: { $0.text == "整块" }),
                               "zhekuai must not surface 整块 (zheng kuai); got top: \(topTexts)")
        }

        /// Same as above, but with the user's typical fuzzy set enabled.
        func testZhekuaiWithFuzzyDoesNotLeakLongerPrefix() throws {
                Engine.prepare()
                let toEnable: [FuzzyPinyinType] = [.ian_iang, .en_eng, .ch_c, .zh_z, .an_ang, .uan_uang, .on_ong, .in_ing, .sh_s]
                let original = FuzzyPinyinSettings.enabledTypes
                for t in toEnable { FuzzyPinyinSettings.setType(t, enabled: true) }
                PinyinSegmentor.resetCaches()
                defer {
                        for t in FuzzyPinyinType.allCases {
                                FuzzyPinyinSettings.setType(t, enabled: original.contains(t))
                        }
                        PinyinSegmentor.resetCaches()
                }
                let text = "zhekuai"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let topTexts = candidates.prefix(15).map(\.text)
                XCTAssertFalse(candidates.contains(where: { $0.text == "整块" }),
                               "zhekuai with fuzzy must not surface 整块; got top: \(topTexts)")
        }
}
