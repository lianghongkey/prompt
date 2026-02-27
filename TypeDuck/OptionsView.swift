import SwiftUI

struct OptionsView: View {

        @EnvironmentObject private var context: AppContext

        private let options: [String] = [
                String(localized: "OptionsView.CharacterForm.HalfWidth"),
                String(localized: "OptionsView.CharacterForm.FullWidth"),
                String(localized: "OptionsView.PunctuationForm.Chinese"),
                String(localized: "OptionsView.PunctuationForm.English")
        ]

        private let characterForm: CharacterForm = Options.characterForm
        private let punctuationForm: PunctuationForm = Options.punctuationForm

        var body: some View {
                let highlightedIndex = context.optionsHighlightedIndex
                VStack(alignment: .leading, spacing: 0) {
                        Group {
                                SettingLabel(index: 0, highlightedIndex: highlightedIndex, text: options[0], checked: characterForm == .halfWidth)
                                SettingLabel(index: 1, highlightedIndex: highlightedIndex, text: options[1], checked: characterForm == .fullWidth)
                        }
                        Divider()
                        Group {
                                SettingLabel(index: 2, highlightedIndex: highlightedIndex, text: options[2], checked: punctuationForm == .chinese)
                                SettingLabel(index: 3, highlightedIndex: highlightedIndex, text: options[3], checked: punctuationForm == .english)
                        }
                }
                .padding(4)
                .roundedHUDVisualEffect()
                .padding(10)
                .fixedSize()
        }
}

private struct SettingLabel: View {

        let index: Int
        let highlightedIndex: Int
        let text: String
        let checked: Bool

        var body: some View {
                let isHighlighted: Bool = index == highlightedIndex
                HStack(spacing: 0) {
                        HStack(spacing: 8) {
                                SerialNumberLabel(index: index).opacity(isHighlighted ? 1 : 0.75)
                                Text(verbatim: text).font(.candidate)
                        }
                        Spacer()
                        Image.checkmark.font(.title3).opacity(checked ? 1 : 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .background(isHighlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
}
