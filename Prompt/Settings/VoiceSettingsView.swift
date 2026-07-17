import SwiftUI
import CoreIME

struct VoiceSettingsView: View {

        @State private var voiceEngine: VoiceEngineKind = AppSettings.voiceEngine
        @State private var whisperModelPath: String = AppSettings.whisperModelPath
        @State private var senseVoiceModelDir: String = AppSettings.senseVoiceModelDir
        // 加载状态由 VoiceRecorder 统一广播（两种引擎共用），反映当前所选引擎。
        @State private var whisperModelLoadState: WhisperModelLoadState = AppSettings.whisperModelLoadState

        @State private var llamaModelPath: String = AppSettings.llamaModelPath
        @State private var correctorServerState: CorrectorServerState = AppSettings.correctorServerState
        @State private var correctorStatusText: String = {
                switch AppSettings.correctorServerState {
                case .notConfigured: return "未设置"
                case .starting: return "加载模型中…"
                case .running: return "已加载"
                case .stopped: return "已卸载"
                case .failed: return "加载失败"
                }
        }()

        @ViewBuilder
        private var whisperStatusDot: some View {
                switch whisperModelLoadState {
                case .notConfigured:
                        Circle().fill(Color.secondary).frame(width: 8, height: 8)
                case .loading:
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                case .loaded:
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                case .failed:
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                }
        }

        private var whisperStatusText: String {
                switch whisperModelLoadState {
                case .notConfigured: return "未设置"
                case .loading:      return "加载中…"
                case .loaded:       return "已加载"
                case .failed:
                        return voiceEngine == .whisper
                                ? "加载失败（请检查路径或 .bin 文件）"
                                : "加载失败（请检查模型目录）"
                }
        }

        @ViewBuilder
        private var correctorStatusDot: some View {
                switch correctorServerState {
                case .notConfigured:
                        Circle().fill(Color.secondary).frame(width: 8, height: 8)
                case .starting:
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                case .running:
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                case .stopped:
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                case .failed:
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                }
        }

        private func applyCorrectorModelPath() {
                AppSettings.updateLlamaModelPath(to: llamaModelPath)
                NotificationCenter.default.post(name: .correctorPathsDidChange, object: nil)
        }

        private func applyWhisperModelPath() {
                AppSettings.updateWhisperModelPath(to: whisperModelPath)
                if whisperModelPath.isEmpty {
                        whisperModelLoadState = .notConfigured
                        NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
                } else {
                        whisperModelLoadState = .loading
                        NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
                }
        }

        private func applySenseVoiceModelDir() {
                AppSettings.updateSenseVoiceModelDir(to: senseVoiceModelDir)
                whisperModelLoadState = senseVoiceModelDir.isEmpty ? .notConfigured : .loading
                NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
        }

        private func applyVoiceEngine(_ engine: VoiceEngineKind) {
                AppSettings.updateVoiceEngine(to: engine)
                whisperModelLoadState = AppSettings.isVoiceModelConfigured ? .loading : .notConfigured
                // VoiceRecorder.reload() 会读取新引擎并广播真实加载状态。
                NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                        Text("识别引擎")
                                                .font(.headline)
                                        Picker("识别引擎", selection: Binding(
                                                get: { voiceEngine },
                                                set: { newValue in
                                                        voiceEngine = newValue
                                                        applyVoiceEngine(newValue)
                                                }
                                        )) {
                                                ForEach(VoiceEngineKind.allCases, id: \.self) { engine in
                                                        Text(engine.displayName).tag(engine)
                                                }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)
                                        Text("Whisper 走 whisper.cpp（.mlmodelc + 同名 .bin）；SenseVoice 走本地 Core ML SenseVoiceSmall（速度更快，支持中英日粤韩）。")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                }
                                .block()
                                .textSelection(.enabled)

                                if voiceEngine == .whisper {
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("语音识别模型路径（.mlmodelc）")
                                                        .font(.headline)
                                                whisperStatusDot
                                                Text(whisperStatusText)
                                                        .font(.caption)
                                                        .foregroundStyle(Color.secondary)
                                        }
                                        NativeTextField(placeholder: "粘贴 .mlmodelc 文件路径", text: $whisperModelPath)
                                                .frame(height: 22)
                                        HStack {
                                                Button("应用") {
                                                        applyWhisperModelPath()
                                                }
                                                if !whisperModelPath.isEmpty {
                                                        Button("清除") {
                                                                whisperModelPath = ""
                                                                AppSettings.updateWhisperModelPath(to: "")
                                                                whisperModelLoadState = .notConfigured
                                                                NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
                                                        }
                                                        .foregroundStyle(Color.red)
                                                }
                                                Spacer()
                                        }
                                        Text("在 Finder 中 Option+右键 → 「将 XX 拷贝为路径名」，粘贴后点应用")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                }
                                .block()
                                .onReceive(NotificationCenter.default.publisher(for: .whisperModelLoadStateDidChange)) { notification in
                                        if let raw = notification.userInfo?["state"] as? String,
                                           let state = WhisperModelLoadState(rawValue: raw) {
                                                whisperModelLoadState = state
                                        }
                                }
                                .textSelection(.enabled)
                                } else {
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("SenseVoice 模型目录")
                                                        .font(.headline)
                                                whisperStatusDot
                                                Text(whisperStatusText)
                                                        .font(.caption)
                                                        .foregroundStyle(Color.secondary)
                                        }
                                        NativeTextField(placeholder: "粘贴 dist 目录路径（含 SenseVoiceSmall.mlmodelc）", text: $senseVoiceModelDir)
                                                .frame(height: 22)
                                        HStack {
                                                Button("应用") {
                                                        applySenseVoiceModelDir()
                                                }
                                                if !senseVoiceModelDir.isEmpty {
                                                        Button("清除") {
                                                                senseVoiceModelDir = ""
                                                                AppSettings.updateSenseVoiceModelDir(to: "")
                                                                whisperModelLoadState = .notConfigured
                                                                NotificationCenter.default.post(name: .whisperModelPathDidChange, object: nil)
                                                        }
                                                        .foregroundStyle(Color.red)
                                                }
                                                Spacer()
                                        }
                                        Text("用 SenseVoiceSmall/build_sensevoice_mlmodelc.sh 生成 dist/ 后，把该目录路径粘贴到此处。")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                }
                                .block()
                                .onReceive(NotificationCenter.default.publisher(for: .whisperModelLoadStateDidChange)) { notification in
                                        if let raw = notification.userInfo?["state"] as? String,
                                           let state = WhisperModelLoadState(rawValue: raw) {
                                                whisperModelLoadState = state
                                        }
                                }
                                .textSelection(.enabled)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("语音纠错模型")
                                                        .font(.headline)
                                                correctorStatusDot
                                                Text(correctorStatusText)
                                                        .font(.caption)
                                                        .foregroundStyle(Color.secondary)
                                        }
                                        NativeTextField(placeholder: "粘贴 .gguf 模型文件路径", text: $llamaModelPath)
                                                .frame(height: 22)
                                        HStack {
                                                Button("应用") {
                                                        applyCorrectorModelPath()
                                                }
                                                if correctorServerState == .running {
                                                        Button("卸载模型") {
                                                                CorrectorEngine.shared.stopServer()
                                                        }
                                                        .foregroundStyle(Color.red)
                                                } else if correctorServerState != .starting {
                                                        Button("加载模型") {
                                                                applyCorrectorModelPath()
                                                                Task {
                                                                        await CorrectorEngine.shared.startServer(userInitiated: true)
                                                                }
                                                        }
                                                        .disabled(llamaModelPath.isEmpty)
                                                }
                                                Spacer()
                                        }
                                        Text("语音识别后自动调用 LLM 纠正文本错误。只需提供 GGUF 模型文件路径。")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                }
                                .block()
                                .onReceive(NotificationCenter.default.publisher(for: .correctorServerStateDidChange)) { notification in
                                        if let raw = notification.userInfo?["state"] as? String,
                                           let state = CorrectorServerState(rawValue: raw) {
                                                correctorServerState = state
                                        }
                                        if let status = notification.userInfo?["status"] as? String, !status.isEmpty {
                                                correctorStatusText = status
                                        }
                                }
                                .textSelection(.enabled)
                                MicrophoneTestView()
                                        .block()
                        }
                        .padding()
                        .frame(minWidth: 300)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("语音输入")
        }
}

#Preview {
        VoiceSettingsView()
}
