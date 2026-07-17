import SwiftUI
import CoreIME

struct VoiceSettingsView: View {

        @State private var senseVoiceModelDir: String = AppSettings.senseVoiceModelDir
        @State private var voiceModelLoadState: VoiceModelLoadState = AppSettings.voiceModelLoadState

        @ViewBuilder
        private var statusDot: some View {
                switch voiceModelLoadState {
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

        private var statusText: String {
                switch voiceModelLoadState {
                case .notConfigured: return "未设置"
                case .loading:      return "加载中…"
                case .loaded:       return "已加载"
                case .failed:       return "加载失败（请检查模型目录）"
                }
        }

        private func applySenseVoiceModelDir() {
                AppSettings.updateSenseVoiceModelDir(to: senseVoiceModelDir)
                voiceModelLoadState = senseVoiceModelDir.isEmpty ? .notConfigured : .loading
                NotificationCenter.default.post(name: .voiceModelDidChange, object: nil)
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("SenseVoice 模型目录")
                                                        .font(.headline)
                                                statusDot
                                                Text(statusText)
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
                                                                voiceModelLoadState = .notConfigured
                                                                NotificationCenter.default.post(name: .voiceModelDidChange, object: nil)
                                                        }
                                                        .foregroundStyle(Color.red)
                                                }
                                                Spacer()
                                        }
                                        Text("用 SenseVoiceSmall/build_sensevoice_mlmodelc.sh 生成 dist/ 后，把该目录路径粘贴到此处。中文待机时 Shift+Space 开始录音，松开结束并插入识别文本。")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                }
                                .block()
                                .onReceive(NotificationCenter.default.publisher(for: .voiceModelLoadStateDidChange)) { notification in
                                        if let raw = notification.userInfo?["state"] as? String,
                                           let state = VoiceModelLoadState(rawValue: raw) {
                                                voiceModelLoadState = state
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
