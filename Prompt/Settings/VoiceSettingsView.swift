import SwiftUI
import CoreIME

struct VoiceSettingsView: View {

        @State private var isEnabled: Bool = AppSettings.isVoiceRecognitionEnabled
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
                case .notConfigured: return "未启用"
                case .loading:      return "加载中…"
                case .loaded:       return "已加载"
                case .failed:       return "加载失败"
                }
        }

        private func applyEnabled() {
                AppSettings.updateVoiceRecognitionEnabled(to: isEnabled)
                voiceModelLoadState = isEnabled ? .loading : .notConfigured
                NotificationCenter.default.post(name: .voiceModelDidChange, object: nil)
        }

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("语音识别")
                                                        .font(.headline)
                                                statusDot
                                                Text(statusText)
                                                        .font(.caption)
                                                        .foregroundStyle(Color.secondary)
                                        }
                                        Toggle("启用语音识别（SenseVoice）", isOn: $isEnabled)
                                                .onChange(of: isEnabled) { _ in
                                                        applyEnabled()
                                                }
                                                .disabled(!AppSettings.isVoiceModelBundled)
                                        if AppSettings.isVoiceModelBundled {
                                                VStack(alignment: .leading, spacing: 6) {
                                                        Text("模型已随 App 打包，无需额外配置。开启后，中文待机时按 Shift+Space 开始录音，松开插入识别文本。")
                                                        if voiceModelLoadState == .loading {
                                                                Text("⏳ 首次开启会为神经引擎（ANE）优化模型，约需 1–2 分钟，请耐心等待，这是一次性的。完成后状态会变为“已加载”，之后每次启动仅需约 1 秒。")
                                                                        .foregroundStyle(Color.orange)
                                                        } else {
                                                                Text("首次开启会为神经引擎优化模型（约 1–2 分钟，一次性）；之后每次启动仅需约 1 秒。")
                                                                        .foregroundStyle(Color.secondary)
                                                        }
                                                }
                                                .font(.caption)
                                        } else {
                                                Text("此版本未包含语音模型。请先运行 SenseVoiceSmall/build_sensevoice_mlmodelc.sh 生成 dist/ 后重新构建 App。")
                                                        .font(.caption)
                                                        .foregroundStyle(Color.red)
                                        }
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
