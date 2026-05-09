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

        /// `zmyan` was previously expected to surface 怎么样 via implicit prefix
        /// extension (yan is a prefix of yang). With the new tokenMatches rule
        /// `.full` tokens require equality (modulo fuzzy), so `yan ≠ yang` unless
        /// the user explicitly enables `an/ang` fuzzy.
        ///
        /// This test asserts both halves: without fuzzy, 怎么样 does NOT appear;
        /// with `an/ang` fuzzy, it does. Pure-abbrev shortcut `zmy → 怎么样` is
        /// covered separately (testZmyShortcutStillWorks) and is unaffected.
        func testZmyanRequiresAnAngFuzzyFor怎么样() throws {
                Engine.prepare()
                let text = "zmyan"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail("no schemes"); return }
                XCTAssertEqual(best.map(\.text), ["z", "m", "yan"])
                XCTAssertEqual(best.map(\.kind), [.abbrev, .abbrev, .full])

                // Without fuzzy: 怎么样 must NOT appear (yan is a complete syllable,
                // engine no longer extends it to yang).
                let original = FuzzyPinyinSettings.enabledTypes
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                PinyinSegmentor.resetCaches()
                defer {
                        for t in FuzzyPinyinType.allCases {
                                FuzzyPinyinSettings.setType(t, enabled: original.contains(t))
                        }
                        PinyinSegmentor.resetCaches()
                }
                let baseCandidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertFalse(baseCandidates.contains(where: { $0.text == "怎么样" }),
                               "zmyan without fuzzy must NOT surface 怎么样; top: \(baseCandidates.prefix(5).map(\.text))")

                // With an/ang fuzzy: yan and yang become equivalent → 怎么样 appears.
                FuzzyPinyinSettings.setType(.an_ang, enabled: true)
                PinyinSegmentor.resetCaches()
                let fuzzySchemes = PinyinSegmentor.segment(text: text)
                let fuzzyCandidates = Engine.suggest(text: text, segmentation: fuzzySchemes, needsSymbols: false)
                XCTAssertTrue(fuzzyCandidates.contains(where: { $0.text == "怎么样" }),
                              "zmyan with an/ang fuzzy should surface 怎么样; top: \(fuzzyCandidates.prefix(5).map(\.text))")
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

        /// User typed "zenmeyan" intending 怎么样 (yang). Previously the engine
        /// extended `yan → yang` via shortcut+prefix fallback. The new rule
        /// requires explicit fuzzy: without `an/ang` fuzzy, 怎么样 must NOT
        /// appear; with it, the fuzzy-equivalent path surfaces it.
        func testZenmeyanRequiresAnAngFuzzyFor怎么样() throws {
                Engine.prepare()
                let text = "zenmeyan"
                let schemes = PinyinSegmentor.segment(text: text)
                guard let best = schemes.first else { XCTFail(); return }
                XCTAssertTrue(best.isAllFull, "zenmeyan should segment as all-full [zen, me, yan]")

                let original = FuzzyPinyinSettings.enabledTypes
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                PinyinSegmentor.resetCaches()
                defer {
                        for t in FuzzyPinyinType.allCases {
                                FuzzyPinyinSettings.setType(t, enabled: original.contains(t))
                        }
                        PinyinSegmentor.resetCaches()
                }
                let baseCandidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertFalse(baseCandidates.contains(where: { $0.text == "怎么样" }),
                               "zenmeyan without fuzzy must NOT surface 怎么样; top: \(baseCandidates.prefix(5).map(\.text))")

                FuzzyPinyinSettings.setType(.an_ang, enabled: true)
                PinyinSegmentor.resetCaches()
                let fuzzySchemes = PinyinSegmentor.segment(text: text)
                let fuzzyCandidates = Engine.suggest(text: text, segmentation: fuzzySchemes, needsSymbols: false)
                XCTAssertTrue(fuzzyCandidates.contains(where: { $0.text == "怎么样" }),
                              "zenmeyan with an/ang fuzzy should surface 怎么样; top: \(fuzzyCandidates.prefix(5).map(\.text))")
        }

        /// Regression for the `gonne → 功能` noise. With `on/ong` fuzzy enabled,
        /// `gon` is fuzzy-resolved to `gong`, segmentation becomes `[gon, ne]`
        /// (all-full). Previously the all-full ping miss fell through to
        /// shortcut+prefix and `"ne" → "neng"` prefix match surfaced 功能
        /// (gong neng) — every token compounded another layer of expansion.
        /// With `.full` tokens restricted to exact-or-fuzzy match, `ne ≠ neng`
        /// and 功能 must not appear.
        func testGonneOnOngFuzzyDoesNotSurface功能() throws {
                Engine.prepare()
                let original = FuzzyPinyinSettings.enabledTypes
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                FuzzyPinyinSettings.setType(.on_ong, enabled: true)
                PinyinSegmentor.resetCaches()
                defer {
                        for t in FuzzyPinyinType.allCases {
                                FuzzyPinyinSettings.setType(t, enabled: original.contains(t))
                        }
                        PinyinSegmentor.resetCaches()
                }
                let text = "gonne"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                XCTAssertFalse(candidates.contains(where: { $0.text == "功能" }),
                               "gonne with on/ong fuzzy must NOT surface 功能; top: \(candidates.prefix(10).map(\.text))")
        }

        /// Regression for the typo-correction guard removal. With `gn → ng`
        /// enabled, `liagne` corrects to `liange`, which has two valid
        /// segmentations: `[liang, e]` and `[lian, ge]`. The previous
        /// `schemeRespectsReplacements` guard rejected `[lian, ge]` (the
        /// swapped pair `ng` straddles its lian|ge boundary), which silently
        /// blocked legitimate candidates like 链格 (lian ge). Now both
        /// segmentations are accepted; under the strict `.full` tokenMatches
        /// rule, the noise case 两根 (liang gen) is still blocked because
        /// `gen ≠ ge`.
        func testLiagneTypoCorrectionSurfacesLiangeCandidates() throws {
                Engine.prepare()
                let originalTypo = TypoCorrectionSettings.enabledTypes
                let originalFuzzy = FuzzyPinyinSettings.enabledTypes
                for t in TypoCorrectionType.allCases { TypoCorrectionSettings.setType(t, enabled: false) }
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                TypoCorrectionSettings.setType(.ng_gn, enabled: true)
                PinyinSegmentor.resetCaches()
                defer {
                        for t in TypoCorrectionType.allCases {
                                TypoCorrectionSettings.setType(t, enabled: originalTypo.contains(t))
                        }
                        for t in FuzzyPinyinType.allCases {
                                FuzzyPinyinSettings.setType(t, enabled: originalFuzzy.contains(t))
                        }
                        PinyinSegmentor.resetCaches()
                }
                let text = "liagne"
                let schemes = PinyinSegmentor.segment(text: text)
                let schemeOrigins = schemes.map { $0.map(\.origin) }
                XCTAssertTrue(schemeOrigins.contains(["liang", "e"]),
                              "[liang, e] must be among schemes; got: \(schemeOrigins)")
                XCTAssertTrue(schemeOrigins.contains(["lian", "ge"]),
                              "[lian, ge] must NOT be filtered out; got: \(schemeOrigins)")

                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let texts = candidates.map(\.text)
                // Any common 2-char word with pinyin "lian ge" demonstrates that
                // [lian, ge] survived the typo-correction filter and ping-matched.
                let lianGeWords = ["恋歌", "连个", "练个", "连歌"]
                XCTAssertTrue(lianGeWords.contains(where: { texts.contains($0) }),
                              "liagne (gn→ng) should surface a [lian, ge] candidate; top: \(texts.prefix(15))")
                XCTAssertFalse(texts.contains("两根"),
                               "liagne must still NOT surface 两根 (liang gen); top: \(texts.prefix(15))")
        }

        /// `liagne` (gn→ng) → 两个 (liang ge) requires `ian/iang` fuzzy.
        ///
        /// Why: corrected `liange` is 6 chars; the only segmentations that fit
        /// are `[liang, e]` and `[lian, ge]` (no `[liang, ge]` — that needs 7
        /// chars). 两个 has syllables `liang ge`, so it can only match via
        /// `[lian, ge]` with token1 = "lian" fuzzy-equivalent to "liang". That
        /// equivalence is exactly what `ian/iang` fuzzy provides; without it
        /// the strict full-token rule (lian ≠ liang) blocks the match.
        func testLiagneSurfaces两个OnlyWithIanIangFuzzy() throws {
                Engine.prepare()
                let originalTypo = TypoCorrectionSettings.enabledTypes
                let originalFuzzy = FuzzyPinyinSettings.enabledTypes
                for t in TypoCorrectionType.allCases { TypoCorrectionSettings.setType(t, enabled: false) }
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                TypoCorrectionSettings.setType(.ng_gn, enabled: true)
                PinyinSegmentor.resetCaches()
                defer {
                        for t in TypoCorrectionType.allCases { TypoCorrectionSettings.setType(t, enabled: originalTypo.contains(t)) }
                        for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: originalFuzzy.contains(t)) }
                        PinyinSegmentor.resetCaches()
                }
                let text = "liagne"
                // Without ian/iang fuzzy: 两个 must NOT appear (lian ≠ liang).
                let baseCandidates = Engine.suggest(text: text, segmentation: PinyinSegmentor.segment(text: text), needsSymbols: false)
                XCTAssertFalse(baseCandidates.contains(where: { $0.text == "两个" }),
                               "without ian/iang fuzzy, liagne must NOT surface 两个; top: \(baseCandidates.prefix(15).map(\.text))")

                // With ian/iang fuzzy: 两个 should surface.
                FuzzyPinyinSettings.setType(.ian_iang, enabled: true)
                PinyinSegmentor.resetCaches()
                let fuzzyCandidates = Engine.suggest(text: text, segmentation: PinyinSegmentor.segment(text: text), needsSymbols: false)
                XCTAssertTrue(fuzzyCandidates.contains(where: { $0.text == "两个" }),
                              "with ian/iang fuzzy, liagne should surface 两个; top: \(fuzzyCandidates.prefix(15).map(\.text))")
        }

        /// Typo-corrected schemes (e.g. liagne → liange) should produce
        /// candidates flagged `isFuzzyMatch = true`, so they sort below true
        /// exact-typed matches in the candidate list. Identical word matched
        /// from typed-`liange` and typed-`liagne` (with gn→ng) should differ
        /// only in this flag.
        func testTypoCorrectedCandidatesAreMarkedFuzzy() throws {
                Engine.prepare()
                let originalTypo = TypoCorrectionSettings.enabledTypes
                let originalFuzzy = FuzzyPinyinSettings.enabledTypes
                for t in TypoCorrectionType.allCases { TypoCorrectionSettings.setType(t, enabled: false) }
                for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: false) }
                TypoCorrectionSettings.setType(.ng_gn, enabled: true)
                PinyinSegmentor.resetCaches()
                defer {
                        for t in TypoCorrectionType.allCases { TypoCorrectionSettings.setType(t, enabled: originalTypo.contains(t)) }
                        for t in FuzzyPinyinType.allCases { FuzzyPinyinSettings.setType(t, enabled: originalFuzzy.contains(t)) }
                        PinyinSegmentor.resetCaches()
                }
                // Typed correctly: 恋歌 should be a non-fuzzy ping match.
                let exactCandidates = Engine.suggest(text: "liange", segmentation: PinyinSegmentor.segment(text: "liange"), needsSymbols: false)
                guard let exactLiange = exactCandidates.first(where: { $0.text == "恋歌" }) else {
                        XCTFail("liange must surface 恋歌; got: \(exactCandidates.prefix(10).map(\.text))"); return
                }
                XCTAssertFalse(exactLiange.isFuzzyMatch, "liange (typed correctly) → 恋歌 must NOT be marked fuzzy")

                // Typed with typo: 恋歌 is reachable only via typo-corrected scheme.
                let typoCandidates = Engine.suggest(text: "liagne", segmentation: PinyinSegmentor.segment(text: "liagne"), needsSymbols: false)
                guard let typoLiange = typoCandidates.first(where: { $0.text == "恋歌" }) else {
                        XCTFail("liagne (with gn→ng) must surface 恋歌; got: \(typoCandidates.prefix(10).map(\.text))"); return
                }
                XCTAssertTrue(typoLiange.isFuzzyMatch, "liagne → 恋歌 must be marked fuzzy (typo-corrected scheme)")
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
