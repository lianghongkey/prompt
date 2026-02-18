import SwiftUI

struct AboutView: View {

        // We'd like to parse Markdown but don't need to localize the text.
        private let typeDuckDescription: AttributedString = {

let source: String = """
欢迎使用 TypeDuck —— 设有少数民族语言提示拼音输入法！有字想打？一装即用，无须再等，即刻打得！
Welcome to TypeDuck: a Mandarin Pinyin input keyboard with minority language prompts! Got something you want to type? Have your fingers ready, get, set, TYPE DUCK!

如有任何查询，欢迎电邮至 [info@typeduck.hk](mailto:info@typeduck.hk?subject=Mac%20TypeDuck%20Enquiry%20/%20Issue%20Report%20%7C%20%E6%8B%BC%E9%9F%B3%E8%BC%B8%E5%85%A5%E6%B3%95%E6%9F%A5%E8%A9%A2%EF%BC%8F%E5%95%8F%E9%A1%8C%E5%8C%AF%E5%A0%B1) 或 [lchaakming@eduhk.hk](mailto:lchaakming@eduhk.hk?subject=Mac%20TypeDuck%20Enquiry%20/%20Issue%20Report%20%7C%20%E6%8B%BC%E9%9F%B3%E8%BC%B8%E5%85%A5%E6%B3%95%E6%9F%A5%E8%A9%A2%EF%BC%8F%E5%95%8F%E9%A1%8C%E5%8C%AF%E5%A0%B1)
Should you have any enquiries, please email [info@typeduck.hk](mailto:info@typeduck.hk?subject=Mac%20TypeDuck%20Enquiry%20/%20Issue%20Report%20%7C%20%E6%8B%BC%E9%9F%B3%E8%BC%B8%E5%85%A5%E6%B3%95%E6%9F%A5%E8%A9%A2%EF%BC%8F%E5%95%8F%E9%A1%8C%E5%8C%AF%E5%A0%B1) or [lchaakming@eduhk.hk](mailto:lchaakming@eduhk.hk?subject=Mac%20TypeDuck%20Enquiry%20/%20Issue%20Report%20%7C%20%E6%8B%BC%E9%9F%B3%E8%BC%B8%E5%85%A5%E6%B3%95%E6%9F%A5%E8%A9%A2%EF%BC%8F%E5%95%8F%E9%A1%8C%E5%8C%AF%E5%A0%B1)

本输入法由香港教育学院语言学及现代语言系开发。特别鸣谢「语文教育及研究常务委员会」资助本计划。
This input method is developed by the Department of Linguistics and Modern Language Studies, the Education University of Hong Kong. Special thanks to the Standing Committee on Language Education and Research for funding this project.
"""

                return (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        }()

        var body: some View {
                ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                                Text("欢迎使用 TypeDuck").font(.title3.bold())
                                Text(typeDuckDescription)
                                VStack {
                                        HStack(spacing: 20) {
                                                Image(.eduhk)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(height: 120)
                                                Image(.lml)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(height: 68)
                                                Image(.crlls)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(height: 84)
                                        }
                                        HStack(spacing: 50) {
                                                Image(.govfunded)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(height: 168)
                                                Image(.scolarlf)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(height: 140)
                                        }
                                }

                                HStack(spacing: 0) {
                                        Spacer()
                                        Text("版本").fontWeight(.semibold)
                                        Text("：").foregroundStyle(Color.secondary)
                                        Text(verbatim: AppSettings.version)
                                        Spacer()
                                }
                                .padding(.top)
                        }
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("关于")
        }
}

#Preview {
        AboutView()
}
