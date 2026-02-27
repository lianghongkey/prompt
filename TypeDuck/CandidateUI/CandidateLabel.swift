import SwiftUI
import CoreIME

struct CandidateLabel: View {

        init(index: Int, candidate: DisplayCandidate, shouldHighlight: Bool) {
                self.labelOpacity = (index == -1) ? 0 : (shouldHighlight ? 1: 0.75)
                self.index = index
                self.candidate = candidate
                self.shouldHighlight = shouldHighlight
                self.isMandarinCandidate = candidate.candidate.isMandarin
        }

        private let labelOpacity: Double
        private let index: Int
        private let candidate: DisplayCandidate
        private let shouldHighlight: Bool
        private let isMandarinCandidate: Bool

        var body: some View {
                HStack {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                                SerialNumberLabel(index: index).opacity(labelOpacity)
                                CandidateContentView(candidate: candidate, hasNotationDisplayButton: false)
                        }
                        Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, isMandarinCandidate ? 0 : 8)
                .contentShape(Rectangle())
        }
}

#if DEBUG
#Preview {
        CandidateLabel(index: 3, candidate: DisplayCandidate(candidate: .example, candidateIndex: 3), shouldHighlight: false)
}
#endif
