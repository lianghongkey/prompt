import SwiftUI

struct AboutView: View {
        var body: some View {
                VStack(spacing: 20) {
                        Spacer()

                        Text("Prompt")
                                .font(.largeTitle.bold())

                        HStack(spacing: 8) {
                                Text("版本")
                                        .foregroundStyle(Color.secondary)
                                Text(verbatim: AppSettings.version)
                                        .fontWeight(.medium)
                        }

                        Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("关于")
        }
}
