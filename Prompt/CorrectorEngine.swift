import Foundation
import os
@preconcurrency import llama

// MARK: - llama_batch 辅助

private func batchClear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
}

private func batchAdd(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seqIds: [llama_seq_id], _ logits: Bool) {
        let i = Int(batch.n_tokens)
        batch.token[i] = id
        batch.pos[i] = pos
        batch.n_seq_id[i] = Int32(seqIds.count)
        for j in 0..<seqIds.count {
                batch.seq_id[i]![j] = seqIds[j]
        }
        batch.logits[i] = logits ? 1 : 0
        batch.n_tokens += 1
}

enum LlamaError: Error, LocalizedError {
        case loadFailed(String)
        var errorDescription: String? {
                switch self {
                case .loadFailed(let m): return m
                }
        }
}

/// 进程内 llama.cpp 推理引擎（C API，经 llama.framework 桥接）。
/// 直接加载 GGUF 并在本进程内推理 —— 无子进程、无 HTTP server、无端口。
/// Metal GPU 推理在输入法进程内可用（Metal kernel 已内嵌进 llama.framework）。
actor LlamaContext {
        // nonisolated(unsafe)：这些 C 指针/句柄只在 actor 内部读写（实际安全），
        // 但 Swift 6 的 nonisolated deinit 需要能访问它们做资源清理。
        nonisolated(unsafe) private let model: OpaquePointer
        nonisolated(unsafe) private let context: OpaquePointer
        nonisolated(unsafe) private let vocab: OpaquePointer
        nonisolated(unsafe) private let sampler: UnsafeMutablePointer<llama_sampler>
        nonisolated(unsafe) private var batch: llama_batch
        private let nCtx: Int32

        private init(model: OpaquePointer, context: OpaquePointer, nCtx: Int32) {
                self.model = model
                self.context = context
                self.nCtx = nCtx
                self.vocab = llama_model_get_vocab(model)
                self.batch = llama_batch_init(Int32(nCtx), 0, 1)

                // 贪心采样（do_sample=False），纠错任务要确定性输出。
                let sparams = llama_sampler_chain_default_params()
                self.sampler = llama_sampler_chain_init(sparams)
                llama_sampler_chain_add(self.sampler, llama_sampler_init_greedy())
        }

        deinit {
                llama_sampler_free(sampler)
                llama_batch_free(batch)
                llama_free(context)
                llama_model_free(model)
                llama_backend_free()
        }

        /// 加载模型并创建推理上下文（阻塞，应在后台线程调用）。
        static func create(modelPath: String, nCtx: Int32 = 2048) throws -> LlamaContext {
                llama_backend_init()

                var modelParams = llama_model_default_params()
                modelParams.n_gpu_layers = 99   // 全部层 offload 到 Metal GPU

                guard let model = llama_model_load_from_file(modelPath, modelParams) else {
                        llama_backend_free()
                        throw LlamaError.loadFailed("无法加载模型: \(modelPath)")
                }

                let nThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
                var ctxParams = llama_context_default_params()
                ctxParams.n_ctx = UInt32(nCtx)
                ctxParams.n_batch = UInt32(nCtx)
                ctxParams.n_threads = nThreads
                ctxParams.n_threads_batch = nThreads

                guard let context = llama_init_from_model(model, ctxParams) else {
                        llama_model_free(model)
                        llama_backend_free()
                        throw LlamaError.loadFailed("无法创建推理上下文")
                }

                return LlamaContext(model: model, context: context, nCtx: nCtx)
        }

        /// 对 ChatML prompt 贪心解码。每解出一段完整 UTF-8 文本就通过 onPiece 回调
        /// （流式，让调用方边收边显示），最终返回完整 assistant 输出。
        func generate(prompt: String, maxTokens: Int, onPiece: @Sendable (String) -> Void) -> String {
                // 重置 KV cache，保证每次纠错相互独立。
                llama_memory_clear(llama_get_memory(context), true)

                let tokens = tokenize(prompt, addSpecial: false, parseSpecial: true)
                guard !tokens.isEmpty, tokens.count < Int(nCtx) else { return "" }

                // 预填充 prompt。
                batchClear(&batch)
                for (i, tok) in tokens.enumerated() {
                        batchAdd(&batch, tok, llama_pos(i), [0], false)
                }
                batch.logits[Int(batch.n_tokens) - 1] = 1   // 只需最后一个 token 的 logits

                guard llama_decode(context, batch) == 0 else { return "" }

                var nCur = batch.n_tokens
                var pending: [UInt8] = []   // 未达 UTF-8 边界、暂存的字节
                var full: [UInt8] = []      // 完整输出（用于返回值）
                var generated = 0

                while generated < maxTokens && nCur < nCtx {
                        let newToken = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
                        if llama_vocab_is_eog(vocab, newToken) { break }

                        let bytes = tokenToBytes(newToken)
                        full.append(contentsOf: bytes)
                        pending.append(contentsOf: bytes)

                        // 只把已构成完整 UTF-8 序列的前缀发出去，残缺的多字节尾部留到下次。
                        let (complete, remainder) = Self.splitValidUTF8(pending)
                        if !complete.isEmpty {
                                onPiece(String(decoding: complete, as: UTF8.self))
                                pending = remainder
                        }

                        batchClear(&batch)
                        batchAdd(&batch, newToken, nCur, [0], true)
                        nCur += 1
                        generated += 1

                        if llama_decode(context, batch) != 0 { break }
                }

                // 收尾：发出残留字节（正常情况下已为空）。
                if !pending.isEmpty {
                        onPiece(String(decoding: pending, as: UTF8.self))
                }
                return String(decoding: full, as: UTF8.self)
        }

        /// 把字节数组切成 (可安全解码的完整前缀, 残缺的多字节尾部)。
        /// 避免在流式输出时把一个中文字符的多个 UTF-8 字节截断成乱码。
        private static func splitValidUTF8(_ bytes: [UInt8]) -> (complete: [UInt8], remainder: [UInt8]) {
                guard !bytes.isEmpty else { return ([], []) }
                var i = bytes.count - 1
                while i > 0 && (bytes[i] & 0xC0) == 0x80 { i -= 1 }   // 跳过续字节 10xxxxxx
                let lead = bytes[i]
                let expected: Int
                if lead & 0x80 == 0 { expected = 1 }
                else if lead & 0xE0 == 0xC0 { expected = 2 }
                else if lead & 0xF0 == 0xE0 { expected = 3 }
                else if lead & 0xF8 == 0xF0 { expected = 4 }
                else { expected = 1 }   // 非法前导字节，按单字节处理
                let available = bytes.count - i
                if available >= expected {
                        return (bytes, [])                                   // 末尾序列完整 → 整段可解码
                } else {
                        return (Array(bytes[..<i]), Array(bytes[i...]))      // 保留残缺尾部
                }
        }

        // MARK: - tokenize / detokenize

        private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> [llama_token] {
                let utf8Count = Int32(text.utf8.count)
                let capacity = Int(utf8Count) + 8
                var tokens = [llama_token](repeating: 0, count: capacity)
                let n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(capacity), addSpecial, parseSpecial)
                if n < 0 { return [] }
                return Array(tokens.prefix(Int(n)))
        }

        private func tokenToBytes(_ token: llama_token) -> [UInt8] {
                var buf = [CChar](repeating: 0, count: 64)
                let n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
                if n < 0 {
                        buf = [CChar](repeating: 0, count: Int(-n))
                        let n2 = llama_token_to_piece(vocab, token, &buf, -n, 0, false)
                        guard n2 > 0 else { return [] }
                        return buf.prefix(Int(n2)).map { UInt8(bitPattern: $0) }
                }
                return buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }
        }
}

// MARK: - CorrectorEngine

/// 进程内中文纠错引擎。
/// 加载 ChineseErrorCorrector4-4B（GGUF）到本进程，语音转写后对整句做语法纠错。
///
/// 注：方法名沿用历史的 server 语义（startServer / stopServer / isServerRunning），
/// 以保持调用方接口稳定；底层已从 llama-server 子进程换成进程内 llama.cpp 推理。
@MainActor
final class CorrectorEngine {

        static let shared = CorrectorEngine()

        /// 模型是否已加载就绪。
        private(set) var isServerRunning: Bool = false
        private var isStarting: Bool = false
        private var userStopped: Bool = false

        private var llama: LlamaContext?

        // ChineseErrorCorrector4-4B 采用 system + user 的纯 ChatML 对话格式（无 <think> 思考块）。
        private let systemPrompt = "假如你是一名专业的纠错专家，请分析输入句子的语法错误类型和修改原因，并只输出纠正后的语句，错误类型如下：错别字、词语搭配错误、词性错误、语序错误、成分残缺、成分赘余、关联词使用错误、指代不明、语义逻辑不通、无误。"

        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "CorrectorEngine")
        private let timing = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "Timing")

        // MARK: - 加载模型（进程内）

        func startServer(userInitiated: Bool = false) async {
                guard !isStarting && !isServerRunning else { return }
                if userInitiated { userStopped = false }
                guard !userStopped else { return }
                isStarting = true
                defer { isStarting = false }

                let modelPath = AppSettings.llamaModelPath
                guard !modelPath.isEmpty else {
                        postState(.notConfigured)
                        return
                }
                guard FileManager.default.fileExists(atPath: modelPath) else {
                        logger.error("模型文件不存在: \(modelPath)")
                        postState(.failed, status: "模型文件不存在")
                        return
                }

                postState(.starting, status: "加载模型…")
                let loadStart = Date()

                do {
                        // 加载是阻塞的 C 调用，放到后台线程，避免冻结主线程。
                        let ctx = try await Task.detached(priority: .userInitiated) {
                                try LlamaContext.create(modelPath: modelPath)
                        }.value
                        llama = ctx
                        isServerRunning = true
                        let modelName = (modelPath as NSString).lastPathComponent
                        let loadMs = Int(Date().timeIntervalSince(loadStart) * 1000)
                        logger.info("纠错模型已加载: \(modelName) (\(loadMs)ms)")
                        postState(.running, status: "就绪 - \(modelName)")
                } catch {
                        logger.error("纠错模型加载失败: \(error.localizedDescription)")
                        postState(.failed, status: "加载失败: \(error.localizedDescription)")
                }
        }

        func stopServer() {
                userStopped = true
                llama = nil   // actor 释放，deinit 中清理 llama.cpp 资源
                isServerRunning = false
                postState(.stopped, status: "已卸载")
        }

        // MARK: - 纠错推理

        /// 流式纠错：每解出一段新内容调用 onToken（在 MainActor 上，且保证顺序），
        /// 全部完成后返回累积的最终文本。失败返回 nil；"" 表示空响应。
        func correctStreaming(
                text: String,
                onToken: @escaping (String) -> Void
        ) async -> String? {
                guard let llama else { return nil }
                timing.info("T7 correctStreaming entry text_len=\(text.count)")

                let prompt =
                        "<|im_start|>system\n\(systemPrompt)<|im_end|>\n" +
                        "<|im_start|>user\n\(text)<|im_end|>\n" +
                        "<|im_start|>assistant\n"

                let genStart = Date()
                timing.info("T8 generate begin")

                // 用 AsyncStream 把后台 actor 解出的 token 顺序送回 MainActor。
                let (stream, continuation) = AsyncStream<String>.makeStream()
                let genTask = Task {
                        let out = await llama.generate(prompt: prompt, maxTokens: 1024) { piece in
                                continuation.yield(piece)
                        }
                        continuation.finish()
                        return out
                }

                // ChineseErrorCorrector4-4B（Qwen3 微调）会强制先输出 <think>…</think>
                // 思维链再给答案，且无法用 /no_think 关闭。流式预览要屏蔽思维链，只把
                // </think> 之后的纠正文本按增量发给 onToken；若本次输出没有 think 块
                // （兜底），则照常流式。
                var raw = ""
                var decided = false        // 是否已判定有无 think 块
                var thinking = false
                var emittedCount = 0       // 已发出的可见文本字符数
                var firstTokenLogged = false
                for await piece in stream {
                        raw += piece
                        if !decided {
                                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty { continue }
                                decided = true
                                thinking = trimmed.hasPrefix("<think")
                        }
                        // 计算当前应可见的文本（思维链阶段为空）。
                        let visible: String
                        if thinking {
                                guard let r = raw.range(of: "</think>") else { continue }
                                visible = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                                visible = raw
                        }
                        let chars = Array(visible)
                        guard chars.count > emittedCount else { continue }
                        if !firstTokenLogged {
                                let firstMs = Int(Date().timeIntervalSince(genStart) * 1000)
                                timing.info("T8a first_visible_token_ms=\(firstMs)")
                                firstTokenLogged = true
                        }
                        onToken(String(chars[emittedCount...]))
                        emittedCount = chars.count
                }

                let output = await genTask.value
                let totalMs = Int(Date().timeIntervalSince(genStart) * 1000)
                let result = stripThinking(output).trimmingCharacters(in: .whitespacesAndNewlines)
                timing.info("T8b generate done took_ms=\(totalMs) total_chars=\(result.count)")
                logger.info("纠错完成: \(text) → \(result)")
                return result
        }

        // MARK: - Internal

        /// 防御性去除 <think>…</think>（该微调模型默认不输出思考块，留作兜底）。
        private func stripThinking(_ text: String) -> String {
                guard let range = text.range(of: "</think>") else { return text }
                return String(text[range.upperBound...])
        }

        private func postState(_ state: CorrectorServerState, status: String? = nil) {
                AppSettings.correctorServerState = state
                NotificationCenter.default.post(
                        name: .correctorServerStateDidChange,
                        object: nil,
                        userInfo: ["state": state.rawValue, "status": status ?? ""]
                )
        }
}
