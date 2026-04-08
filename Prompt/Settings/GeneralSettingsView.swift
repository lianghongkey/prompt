import SwiftUI
import CoreIME

struct GeneralSettingsView: View {

        @State private var pageSize: Int = AppSettings.candidatePageSize
        private let pageSizeRange: Range<Int> = AppSettings.candidatePageSizeRange

        @State private var isEmojiSuggestionsOn: Bool = Options.isEmojiSuggestionsOn
        @State private var isInputMemoryOn: Bool = AppSettings.isInputMemoryOn

        @State private var isClearInputMemoryConfirmDialogPresented: Bool = false
        @State private var isPerformingClearInputMemory: Bool = false
        @State private var clearInputMemoryProgress: Double = 0
        private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

        @State private var whisperModelPath: String = AppSettings.whisperModelPath
        @State private var whisperModelLoadState: WhisperModelLoadState = AppSettings.whisperModelLoadState

        @State private var llamaModelPath: String = AppSettings.llamaModelPath
        @State private var correctorServerState: CorrectorServerState = AppSettings.correctorServerState
        @State private var correctorStatusText: String = {
                switch AppSettings.correctorServerState {
                case .notConfigured: return "未设置"
                case .starting: return "启动中…"
                case .running: return "运行中"
                case .stopped: return "已停止"
                case .failed: return "启动失败"
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
                case .failed:       return "加载失败（请检查路径或 .bin 文件）"
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

        var body: some View {
                ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                        Picker("每页候选词数量", selection: $pageSize) {
                                                ForEach(pageSizeRange, id: \.self) {
                                                        Text(verbatim: "\($0)").tag($0)
                                                }
                                        }
                                        .pickerStyle(.menu)
                                        .scaledToFit()
                                        .onChange(of: pageSize) { newPageSize in
                                                AppSettings.updateCandidatePageSize(to: newPageSize)
                                        }
                                        Spacer()
                                }
                                .block()
                                HStack {
                                        Toggle("表情符号建议", isOn: $isEmojiSuggestionsOn)
                                                .toggleStyle(.switch)
                                                .scaledToFit()
                                                .onChange(of: isEmojiSuggestionsOn) { newState in
                                                        Options.updateEmojiSuggestions(to: newState)
                                                }
                                        Spacer()
                                }
                                .block()
                                VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                                Toggle("输入记忆", isOn: $isInputMemoryOn)
                                                        .toggleStyle(.switch)
                                                        .scaledToFit()
                                                        .onChange(of: isInputMemoryOn) { newState in
                                                                AppSettings.updateInputMemory(to: newState)
                                                        }
                                                Spacer()
                                        }
                                        HStack {
                                                Button(role: .destructive) {
                                                        isClearInputMemoryConfirmDialogPresented = true
                                                } label: {
                                                        Text("清空输入记忆")
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .foregroundStyle(Color.red)
                                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                .confirmationDialog("清空输入记忆？", isPresented: $isClearInputMemoryConfirmDialogPresented) {
                                                        Button("清空", role: .destructive) {
                                                                clearInputMemoryProgress = 0
                                                                isPerformingClearInputMemory = true
                                                                UserLexicon.deleteAll()
                                                        }
                                                        Button("取消", role: .cancel) {
                                                                isClearInputMemoryConfirmDialogPresented = false
                                                        }
                                                }
                                                ProgressView(value: clearInputMemoryProgress)
                                                        .frame(width: 100)
                                                        .opacity(isPerformingClearInputMemory ? 1 : 0)
                                                        .onReceive(timer) { _ in
                                                                guard isPerformingClearInputMemory else { return }
                                                                if clearInputMemoryProgress > 1 {
                                                                        isPerformingClearInputMemory = false
                                                                } else {
                                                                        clearInputMemoryProgress += 0.1
                                                                }
                                                        }
                                                Spacer()
                                        }
                                }
                                .block()
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
                                VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                                Text("语音纠错服务")
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
                                                        Button("停止服务") {
                                                                CorrectorEngine.shared.stopServer()
                                                        }
                                                        .foregroundStyle(Color.red)
                                                } else if correctorServerState != .starting {
                                                        Button("启动服务") {
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
                .navigationTitle("设置")
        }
}

/// NSTextField wrapper that reliably handles paste (Cmd+V) regardless of IME state.
private struct NativeTextField: NSViewRepresentable {
        let placeholder: String
        @Binding var text: String

        func makeNSView(context: Context) -> NSTextField {
                let field = NSTextField()
                field.placeholderString = placeholder
                field.delegate = context.coordinator
                field.bezelStyle = .roundedBezel
                field.cell?.isScrollable = true
                field.cell?.wraps = false
                return field
        }

        func updateNSView(_ field: NSTextField, context: Context) {
                if field.stringValue != text {
                        field.stringValue = text
                }
        }

        func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

        final class Coordinator: NSObject, NSTextFieldDelegate {
                @Binding var text: String
                init(text: Binding<String>) { _text = text }
                func controlTextDidChange(_ obj: Notification) {
                        if let field = obj.object as? NSTextField {
                                text = field.stringValue
                        }
                }
        }
}

#Preview {
        GeneralSettingsView()
}
