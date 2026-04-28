import SwiftUI

struct MotherBoard: View {

        @EnvironmentObject private var context: AppContext

        var body: some View {
                ZStack(alignment: context.quadrant.alignment) {
                        Color.clear
                        if let indicator = context.recordingIndicator {
                                Text(indicator)
                                        .font(.system(size: 24))
                                        .padding(6)
                                        .roundedHUDVisualEffect()
                                        .padding(10)
                                        .fixedSize()
                        } else if let mode = context.modeIndicator {
                                Text(mode)
                                        .font(.candidate)
                                        .foregroundStyle(Color.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .padding(4)
                                        .roundedHUDVisualEffect()
                                        .padding(10)
                                        .fixedSize()
                        } else if context.inputForm.isOptions {
                                OptionsView()
                        } else if context.isClean && (context.filterIndicator == nil) {
                                EmptyView()
                        } else {
                                CandidateBoard()
                        }
                }
        }
}
