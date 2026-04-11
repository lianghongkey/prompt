import XCTest
@testable import CoreIME

final class CoreIMETests: XCTestCase {

        // MARK: - Segmentor

        /*
        func testSegment() throws {
                let sourceText: String = "neihou"
                let expected: [[String]] = [["nei", "hou"], ["nei", "ho"], ["nei"], ["ne"]]
                let result = Segmentor.segment(sourceText)
                XCTAssertEqual(result, expected)
        }
        func testScheme() throws {
                let sourceText: String = "neihou"
                let result = Segmentor.scheme(of: sourceText)
                XCTAssertEqual(result, ["nei", "hou"])
        }
        */


        // MARK: - Reverse Lookup

        func testPinyinSegmentor() throws {
                let text: String = "putonghuapinyin"
                let schemes: Segmentation = PinyinSegmentor.segment(text: text)
                if let scheme = schemes.first {
                        let syllables = scheme.map(\.text)
                        XCTAssertEqual(syllables, ["pu", "tong", "hua", "pin", "yin"])
                } else {
                        XCTFail("No schemes")
                }
        }

        func testGengaoxiaoSegmentation() throws {
                let text = "gengaoxiao"
                let schemes = PinyinSegmentor.segment(text: text)
                let topLen = schemes.first?.length ?? 0
                let top = schemes.filter { $0.length == topLen }.map { $0.map(\.text) }
                XCTAssertTrue(top.contains(["gen", "gao", "xiao"]), "gen+gao+xiao should be a top segmentation")
                XCTAssertTrue(top.contains(["geng", "ao", "xiao"]), "geng+ao+xiao should be a top segmentation")
        }

        /// Tail-drop fallback must run for every top scheme, not just whichever one
        /// `segmentation.first` happens to return when lengths tie. Otherwise, for
        /// "gengaoxiao", only one of "更傲" (geng+ao) and "根高" (gen+gao) would show
        /// up depending on Swift's unstable sort.
        func testGengaoxiaoSuggest() throws {
                Engine.prepare()
                let text = "gengaoxiao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let texts = candidates.map(\.text)
                XCTAssertTrue(texts.contains("根高"), "gen+gao fallback should surface 根高; got \(texts)")
                XCTAssertTrue(texts.contains("更傲"), "geng+ao fallback should surface 更傲; got \(texts)")
        }

        /// Fallback must descend all the way to a single syllable, so every prefix
        /// interpretation (gen / geng / ge) produces single-char candidates — not just
        /// the first syllable of whichever scheme `segmentation.first` happens to return.
        func testGengaoxiaoSingleSyllableFallback() throws {
                Engine.prepare()
                let text = "gengaoxiao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                let gen = candidates.first(where: { $0.text == "根" && $0.romanization == "gen" })
                let geng = candidates.first(where: { $0.text == "更" && $0.romanization == "geng" })
                XCTAssertNotNil(gen, "gen fallback should surface 根")
                XCTAssertNotNil(geng, "geng fallback should surface 更")

                // Single-char candidates must come after multi-syllable matches (longer
                // input ranks higher), so 根高/更傲 must still outrank 根/更.
                let idxGenGao = candidates.firstIndex(where: { $0.text == "根高" }) ?? Int.max
                let idxGen = candidates.firstIndex(where: { $0.text == "根" && $0.romanization == "gen" }) ?? Int.max
                XCTAssertLessThan(idxGenGao, idxGen, "2-syllable 根高 should rank above single-char 根")
        }

        /// Regression: typical 2-syllable input must still work and rank the full-length
        /// match first, with single-char fallbacks trailing.
        func testZhidaoOrdering() throws {
                Engine.prepare()
                let text = "zhidao"
                let schemes = PinyinSegmentor.segment(text: text)
                let candidates = Engine.suggest(text: text, segmentation: schemes, needsSymbols: false)
                guard let top = candidates.first else {
                        XCTFail("no candidates for zhidao")
                        return
                }
                XCTAssertEqual(top.text, "知道", "top candidate for zhidao should be 知道")
                XCTAssertEqual(top.input, "zhidao")
        }

        // MARK: - Max Syllable Count

        func testMaxSyllableCount() throws {
                // Single letter - one potential syllable
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "l"), 1, "l should be 1")

                // Two letters that are two separate initials
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lh"), 2, "lh should be 2")

                // Complete single syllable
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "li"), 1, "li should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lian"), 1, "lian should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liang"), 1, "liang should be 1")

                // Complete syllable + partial syllable
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "lianh"), 2, "lianh should be 2 (lian + h)")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liangh"), 2, "liangh should be 2 (liang + h)")

                // Two complete syllables
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "liangho"), 2, "liangho should be 2 (liang + ho)")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "nihao"), 2, "nihao should be 2 (ni + hao)")

                // Single syllable
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "ni"), 1, "ni should be 1")

                // Two initials
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "nh"), 2, "nh should be 2")

                // Two-letter initials (zh, ch, sh)
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zh"), 1, "zh should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zhi"), 1, "zhi should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "zhih"), 2, "zhih should be 2")

                // Zero-initial syllables
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "a"), 1, "a should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "an"), 1, "an should be 1")
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: "anh"), 2, "anh should be 2")

                // Empty string
                XCTAssertEqual(PinyinSegmentor.maxSyllableCount(for: ""), 0, "empty should be 0")
        }

        /*
        func testPinyinLookup() throws {
                Engine.prepare()
                let result: String = Engine.pinyinLookup(for: "wo").first!.text
                XCTAssertEqual(result, "我")
        }

        func testCangjie() throws {
                Engine.prepare()
                let result: String = Engine.cangjieLookup(for: "dam").first!.text
                XCTAssertEqual(result, "查")
        }
        func testStroke() throws {
                Engine.prepare()
                let result: String = Engine.strokeLookup(for: "wsad").first!.text
                XCTAssertEqual(result, "木")
        }

        func testLeungFan() {
                Engine.prepare()
                let result: String = Engine.leungFanLookup(for: "mukdaan").first!.text
                XCTAssertEqual(result, "查")
        }
        */


        // MARK: - Emoji

        /*
        func testEmoji() throws {
                let emojis: [[String]] = EmojiSource.fetchAll()
                XCTAssertEqual(emojis.count, 8)
                XCTAssertEqual(emojis[0].count, 480)
                XCTAssertEqual(emojis[1].count, 204)
                XCTAssertEqual(emojis[2].count, 126)
                XCTAssertEqual(emojis[3].count, 118)
                XCTAssertEqual(emojis[4].count, 131)
                XCTAssertEqual(emojis[5].count, 222)
                XCTAssertEqual(emojis[6].count, 293)
                XCTAssertEqual(emojis[7].count, 259)
                XCTAssertNotEqual(emojis[0][0], "?")
        }
        */
}

