import CoreML
import Foundation

/// SenseVoiceSmall 的纯 Swift 端上推理引擎（原生 Core ML）。
///
/// 管线（与上游 `sensevoice_ane/inference.py` 逐步对齐）：
///   16k mono PCM → fbank(80) → LFR(7,6)→560 → CMVN → 拼 4 前缀 token
///   → ×√512 → 正弦位置编码 → pad 到枚举桶 → Core ML predict
///   → CTC 贪心解码 → tokens.json 反查 → 剥 `<|...|>` 标签
///
/// 依赖一个"模型目录"（build_sensevoice_mlmodelc.sh 产出的 dist/），内含：
///   SenseVoiceSmall.mlmodelc, query_embeddings.f32, am.mvn, tokens.json
public final class SenseVoiceEngine {

        public enum EngineError: Error, LocalizedError {
                case missingFile(String)
                case badEmbedding
                case badCMVN
                case audioTooLong
                case predictionFailed(String)
                public var errorDescription: String? {
                        switch self {
                        case .missingFile(let f): return "模型目录缺少文件：\(f)"
                        case .badEmbedding:       return "query_embeddings.f32 尺寸不对（应为 16×560 float32）"
                        case .badCMVN:            return "am.mvn 解析失败"
                        case .audioTooLong:       return "音频过长（此转换最长约 30s）"
                        case .predictionFailed(let m): return "Core ML 推理失败：\(m)"
                        }
                }
        }

        // 枚举序列长度桶（含 4 个前缀 token），约 1s–30s
        static let seqBuckets = [21, 38, 54, 88, 171, 254, 338, 504]
        static let featDim = 560
        static let vocabSize = 25055
        static let modelScale = Float(512).squareRoot()

        // language / textnorm 前缀 id（对齐 inference.py）
        public enum Language: Int { case auto = 0, zh = 3, en = 4, yue = 7, ja = 11, ko = 12 }
        public enum TextNorm: Int { case withITN = 14, withoutITN = 15 }

        private let model: MLModel
        private let embeddings: [Float]      // 16 * 560，行主序
        private let cmvnAdd: [Float]         // 560
        private let cmvnRescale: [Float]     // 560
        private let tokens: [String]
        private let fbank = Fbank()

        // MARK: 加载

        public init(modelDir: URL) throws {
                func need(_ name: String) throws -> URL {
                        let u = modelDir.appendingPathComponent(name)
                        guard FileManager.default.fileExists(atPath: u.path) else { throw EngineError.missingFile(name) }
                        return u
                }
                let mlmodelc = try need("SenseVoiceSmall.mlmodelc")
                let embURL = try need("query_embeddings.f32")
                let mvnURL = try need("am.mvn")
                let tokURL = try need("tokens.json")

                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: mlmodelc, configuration: config)

                // 前缀 embedding 表 (16, 560) float32
                let embData = try Data(contentsOf: embURL)
                guard embData.count == 16 * Self.featDim * 4 else { throw EngineError.badEmbedding }
                embeddings = embData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

                // CMVN
                let (add, rescale) = try Self.parseCMVN(mvnURL)
                cmvnAdd = add
                cmvnRescale = rescale

                // 词表
                let tokData = try Data(contentsOf: tokURL)
                tokens = try JSONDecoder().decode([String].self, from: tokData)
        }

        /// 解析 am.mvn 的 <AddShift> 与 <Rescale> 两个 560 维向量。
        static func parseCMVN(_ url: URL) throws -> ([Float], [Float]) {
                let text = try String(contentsOf: url, encoding: .utf8)
                func vec(_ tag: String) throws -> [Float] {
                        guard let tagRange = text.range(of: "<\(tag)>"),
                              let lb = text.range(of: "[", range: tagRange.upperBound ..< text.endIndex),
                              let rb = text.range(of: "]", range: lb.upperBound ..< text.endIndex)
                        else { throw EngineError.badCMVN }
                        let body = text[lb.upperBound ..< rb.lowerBound]
                        let vals = body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                                .compactMap { Float($0) }
                        guard vals.count == Self.featDim else { throw EngineError.badCMVN }
                        return vals
                }
                return (try vec("AddShift"), try vec("Rescale"))
        }

        // MARK: 推理

        /// 转写 16kHz 单声道 float PCM。返回纯文本（已剥离标签）。
        public func transcribe(samples: [Float],
                               language: Language = .auto,
                               textnorm: TextNorm = .withITN) throws -> String {
                // 1. fbank → LFR → CMVN
                let fb = fbank.compute(samples)
                if fb.isEmpty { return "" }
                var feats = applyLFR(fb)                 // (T, 560)
                applyCMVN(&feats)

                // 2. 长度保护：T + 4 前缀 ≤ 504
                let maxFeat = Self.seqBuckets.last! - 4
                if feats.count > maxFeat { feats = Array(feats.prefix(maxFeat)) }

                // 3. 拼 4 个前缀 embedding：[language, event(1), emotion(2), textnorm]
                let prefixRows = [language.rawValue, 1, 2, textnorm.rawValue]
                var seq: [[Float]] = []
                seq.reserveCapacity(feats.count + 4)
                for r in prefixRows {
                        seq.append(Array(embeddings[r * Self.featDim ..< (r + 1) * Self.featDim]))
                }
                seq.append(contentsOf: feats)
                let actualLen = seq.count

                // 4. ×√512
                for t in 0 ..< actualLen {
                        for c in 0 ..< Self.featDim { seq[t][c] *= Self.modelScale }
                }

                // 5. 正弦位置编码（FunASR SinusoidalPositionEncoder，depth=560，位置从 1 起）
                addPositionalEncoding(&seq)

                // 6. pad 到最近的桶
                let targetLen = nearestBucket(actualLen)

                // 7. 组装 Core ML 输入 encoder_input: (1, 560, 1, targetLen) float16
                let input = try makeInput(seq, targetLen: targetLen)
                let provider = try MLDictionaryFeatureProvider(dictionary: ["encoder_input": input])
                let out: MLFeatureProvider
                do { out = try model.prediction(from: provider) }
                catch { throw EngineError.predictionFailed(error.localizedDescription) }
                guard let logits = out.featureValue(for: "ctc_logits")?.multiArrayValue else {
                        throw EngineError.predictionFailed("缺少 ctc_logits 输出")
                }

                // 8. CTC 贪心解码 → 文本
                let ids = ctcGreedy(logits, actualLen: actualLen, targetLen: targetLen)
                return detokenize(ids)
        }

        /// 调试用：返回 fbank→LFR→CMVN 后的 (T,560) 特征，用于和参考实现逐值比对。
        public func debugCMVNFeatures(_ samples: [Float]) -> [[Float]] {
                let fb = fbank.compute(samples)
                if fb.isEmpty { return [] }
                var feats = applyLFR(fb)
                applyCMVN(&feats)
                return feats
        }

        // MARK: 各步实现

        private func applyLFR(_ feats: [[Float]], m: Int = 7, n: Int = 6) -> [[Float]] {
                let D = 80
                var f = feats
                let T0 = f.count
                let padLen = (n - (T0 % n)) % n
                if padLen > 0 { f.append(contentsOf: Array(repeating: [Float](repeating: 0, count: D), count: padLen)) }
                let T = f.count
                let nLfr = T / n
                let zeros = [Float](repeating: 0, count: D)
                var out = [[Float]](repeating: [Float](repeating: 0, count: m * D), count: nLfr)
                for i in 0 ..< nLfr {
                        let start = i * n
                        for j in 0 ..< m {
                                let idx = start + j
                                let src = idx < T ? f[idx] : zeros
                                let base = j * D
                                for d in 0 ..< D { out[i][base + d] = src[d] }
                        }
                }
                return out
        }

        private func applyCMVN(_ feats: inout [[Float]]) {
                for t in 0 ..< feats.count {
                        for c in 0 ..< Self.featDim {
                                feats[t][c] = (feats[t][c] + cmvnAdd[c]) * cmvnRescale[c]
                        }
                }
        }

        private func addPositionalEncoding(_ seq: inout [[Float]]) {
                let depth = Self.featDim
                let half = depth / 2                       // 280
                let logTimescale = log(10000.0) / Double(half - 1)
                var invTs = [Double](repeating: 0, count: half)
                for d in 0 ..< half { invTs[d] = exp(Double(d) * -logTimescale) }
                for p in 0 ..< seq.count {
                        let pos = Double(p + 1)             // 位置从 1 起
                        for d in 0 ..< half {
                                let s = pos * invTs[d]
                                seq[p][d]        += Float(sin(s))
                                seq[p][half + d] += Float(cos(s))
                        }
                }
        }

        private func nearestBucket(_ len: Int) -> Int {
                for b in Self.seqBuckets where b >= len { return b }
                return Self.seqBuckets.last!
        }

        private func makeInput(_ seq: [[Float]], targetLen: Int) throws -> MLMultiArray {
                let arr = try MLMultiArray(shape: [1, NSNumber(value: Self.featDim), 1, NSNumber(value: targetLen)],
                                          dataType: .float16)
                let ptr = arr.dataPointer.bindMemory(to: Float16.self, capacity: Self.featDim * targetLen)
                // 布局 (1,560,1,T)：offset(c,t) = c*targetLen + t；pad 区域为 0
                for c in 0 ..< Self.featDim {
                        let rowBase = c * targetLen
                        for t in 0 ..< targetLen {
                                ptr[rowBase + t] = t < seq.count ? Float16(seq[t][c]) : 0
                        }
                }
                return arr
        }

        private func ctcGreedy(_ logits: MLMultiArray, actualLen: Int, targetLen: Int) -> [Int] {
                // 输出形状 (1, 25055, 1, T)。用真实 strides / dataType，不假设内存连续。
                let shape = logits.shape.map { $0.intValue }
                let strides = logits.strides.map { $0.intValue }
                // 维度：[batch, vocab, 1, time]
                let vocabDim = shape.count >= 4 ? 1 : 0
                let timeDim = shape.count - 1
                let vStride = strides[vocabDim]
                let tStride = strides[timeDim]
                let vocab = shape[vocabDim]
                let base = logits.dataPointer
                // 读取器：按 dataType 取值
                let read: (Int) -> Float
                switch logits.dataType {
                case .float16:
                        let p = base.bindMemory(to: Float16.self, capacity: logits.count)
                        read = { Float(p[$0]) }
                case .float32:
                        let p = base.bindMemory(to: Float.self, capacity: logits.count)
                        read = { p[$0] }
                case .double:
                        let p = base.bindMemory(to: Double.self, capacity: logits.count)
                        read = { Float(p[$0]) }
                default:
                        read = { _ in 0 }
                }

                var ids: [Int] = []
                ids.reserveCapacity(actualLen)
                for t in 0 ..< actualLen {
                        let tOff = t * tStride
                        var best = 0
                        var bestVal = read(tOff)                // v=0
                        var off = tOff + vStride                // v=1
                        for v in 1 ..< vocab {
                                let val = read(off)
                                if val > bestVal { bestVal = val; best = v }
                                off += vStride
                        }
                        ids.append(best)
                }
                // 去连续重复 + 去 blank(0)
                var decoded: [Int] = []
                var prev = -1
                for id in ids {
                        if id != prev && id != 0 { decoded.append(id) }
                        prev = id
                }
                return decoded
        }

        private static let tagRegex = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>")

        private func detokenize(_ ids: [Int]) -> String {
                var s = ""
                for id in ids where id >= 0 && id < tokens.count { s += tokens[id] }
                s = s.replacingOccurrences(of: "\u{2581}", with: " ")   // SentencePiece 词界
                let range = NSRange(s.startIndex..., in: s)
                s = Self.tagRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
}
