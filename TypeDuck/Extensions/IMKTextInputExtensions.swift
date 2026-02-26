import Foundation
import InputMethodKit

extension IMKTextInput {

        /// (x: origin.x, y: origin.y: width 1, height: maxY)
        var cursorBlock: CGRect {
                var lineHeightRectangle: CGRect = .init()
                // Try with selected range location first
                let cursorIndex = self.selectedRange().location
                let index = (cursorIndex == NSNotFound) ? 0 : cursorIndex
                self.attributes(forCharacterIndex: index, lineHeightRectangle: &lineHeightRectangle)
                if lineHeightRectangle.height > 0 {
                        return lineHeightRectangle
                }
                // Fallback: try with index 0
                if index != 0 {
                        self.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRectangle)
                        if lineHeightRectangle.height > 0 {
                                return lineHeightRectangle
                        }
                }
                // Fallback: try firstRect for marked range
                let marked = self.markedRange()
                if marked.location != NSNotFound {
                        var actualRange = NSRange()
                        let rect = self.firstRect(forCharacterRange: marked, actualRange: &actualRange)
                        if rect.height > 0 {
                                return rect
                        }
                }
                return lineHeightRectangle
        }
}
