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
                        }
                        .textSelection(.enabled)
                        .padding()
                        .frame(minWidth: 300)
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("设置")
        }
}

#Preview {
        GeneralSettingsView()
}
