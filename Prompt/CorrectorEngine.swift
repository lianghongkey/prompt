import Foundation
import os

/// llama.cpp server 推理引擎
/// 管理 llama-server 子进程生命周期，通过 OpenAI 兼容 API 调用纠错推理。
@MainActor
final class CorrectorEngine {

        static let shared = CorrectorEngine()

        private(set) var isServerRunning: Bool = false
        private var serverProcess: Process?
        private var isStarting: Bool = false
        private var userStopped: Bool = false
        private let port = 8081
        private let host = "127.0.0.1"
        private let prompt = "你是一个文本纠错专家，纠正输入句子中的语法错误，并输出正确的句子，输入句子为："

        private let logger = Logger(subsystem: "hk.eduhk.inputmethod.Prompt", category: "CorrectorEngine")

        // MARK: - 启动 llama-server

        func startServer(userInitiated: Bool = false) async {
                guard !isStarting && !isServerRunning else { return }
                if userInitiated { userStopped = false }
                guard !userStopped else { return }
                isStarting = true
                defer { isStarting = false }

                let serverBin = AppSettings.llamaServerPath
                let modelPath = AppSettings.llamaModelPath

                guard !serverBin.isEmpty && !modelPath.isEmpty else {
                        postState(.notConfigured)
                        return
                }

                // Check if a server is already running on the port
                if await checkHealth() {
                        isServerRunning = true
                        logger.info("检测到已有 llama-server 在端口 \(self.port) 运行")
                        postState(.running, status: "就绪（已有服务）")
                        return
                }

                guard FileManager.default.fileExists(atPath: serverBin) else {
                        logger.error("llama-server 不存在: \(serverBin)")
                        postState(.failed, status: "llama-server 文件不存在")
                        return
                }
                guard FileManager.default.fileExists(atPath: modelPath) else {
                        logger.error("模型文件不存在: \(modelPath)")
                        postState(.failed, status: "模型文件不存在")
                        return
                }

                postState(.starting, status: "启动 llama-server…")

                let process = Process()
                process.executableURL = URL(fileURLWithPath: serverBin)
                process.arguments = [
                        "-m", modelPath,
                        "--host", host,
                        "--port", String(port),
                        "-ngl", "99",
                        "--seed", "42",
                        "-c", "1024",
                ]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                        try process.run()
                } catch {
                        logger.error("llama-server 启动失败: \(error.localizedDescription)")
                        postState(.failed, status: "启动失败: \(error.localizedDescription)")
                        return
                }
                serverProcess = process
                logger.info("llama-server 进程已启动, pid=\(process.processIdentifier)")

                let ready = await waitForServer(timeout: 30)
                if ready {
                        isServerRunning = true
                        let modelName = (modelPath as NSString).lastPathComponent
                        postState(.running, status: "就绪 - \(modelName)")
                        logger.info("llama-server 已就绪: \(modelName)")
                } else {
                        let wasAlive = serverProcess?.isRunning ?? false
                        logger.error("llama-server 启动超时, processAlive=\(wasAlive)")
                        terminateProcess()
                        postState(.failed, status: wasAlive ? "启动超时（服务未就绪）" : "进程已退出")
                }
        }

        func stopServer() {
                userStopped = true
                terminateProcess()
                isServerRunning = false
                postState(.stopped, status: "已停止")
        }

        // MARK: - 纠错推理

        func correct(text: String) async -> String? {
                guard isServerRunning else { return nil }

                let url = URL(string: "http://\(host):\(port)/v1/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 10

                let body: [String: Any] = [
                        "messages": [
                                ["role": "user", "content": prompt + text]
                        ],
                        "max_tokens": 1024,
                        "temperature": 0,
                        "seed": 42,
                ]

                do {
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                logger.error("纠错请求 HTTP 失败")
                                return nil
                        }
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let message = choices.first?["message"] as? [String: Any],
                              let content = message["content"] as? String else {
                                logger.error("纠错响应解析失败")
                                return nil
                        }
                        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        logger.info("纠错完成: \(text) → \(result)")
                        return result
                } catch {
                        logger.error("纠错请求失败: \(error.localizedDescription)")
                        return nil
                }
        }

        // MARK: - Internal

        private func checkHealth() async -> Bool {
                let healthURL = URL(string: "http://\(host):\(port)/health")!
                guard let (_, response) = try? await URLSession.shared.data(from: healthURL),
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        return false
                }
                return true
        }

        private func waitForServer(timeout: Int) async -> Bool {
                for i in 0..<(timeout * 2) {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if let proc = serverProcess, !proc.isRunning {
                                logger.error("llama-server 进程提前退出, terminationStatus=\(proc.terminationStatus)")
                                return false
                        }
                        if await checkHealth() {
                                return true
                        }
                        if i == 0 {
                                logger.debug("等待 llama-server 就绪…")
                        }
                }
                return false
        }

        private func terminateProcess() {
                serverProcess?.terminate()
                serverProcess = nil
        }

        private func postState(_ state: CorrectorServerState, status: String? = nil) {
                AppSettings.correctorServerState = state
                NotificationCenter.default.post(
                        name: .correctorServerStateDidChange,
                        object: nil,
                        userInfo: ["state": state.rawValue, "status": status ?? ""]
                )
        }

        deinit {
                serverProcess?.terminate()
        }
}
