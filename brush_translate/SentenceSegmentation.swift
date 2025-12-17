import Foundation

struct SentenceRenderSegment: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let componentID: SentenceComponentID?
}

enum SentenceSegmentation {
    static func segments(sourceText: String, components: [SentenceAnalysis.Component]) -> [SentenceRenderSegment]? {
        let utf16Count = sourceText.utf16.count
        let sorted = components.sorted { $0.start < $1.start }

        var cursor = 0
        var result: [SentenceRenderSegment] = []

        for component in sorted {
            guard component.start >= cursor, component.end >= component.start, component.end <= utf16Count else {
                return nil
            }

            if component.start > cursor {
                guard let gap = sourceText.substring(utf16Range: cursor..<component.start) else { return nil }
                if !gap.isEmpty {
                    result.append(SentenceRenderSegment(text: gap, componentID: nil))
                }
            }

            let componentID = SentenceComponentID(start: component.start, end: component.end)
            guard let slice = sourceText.substring(utf16Range: component.start..<component.end) else { return nil }
            if !slice.isEmpty {
                result.append(SentenceRenderSegment(text: slice, componentID: componentID))
            }
            cursor = component.end
        }

        if cursor < utf16Count {
            guard let tail = sourceText.substring(utf16Range: cursor..<utf16Count) else { return nil }
            if !tail.isEmpty {
                result.append(SentenceRenderSegment(text: tail, componentID: nil))
            }
        }

        return result
    }
}

private extension String {
    func substring(utf16Range: Range<Int>) -> String? {
        guard utf16Range.lowerBound >= 0, utf16Range.upperBound <= utf16.count else { return nil }
        let lower = utf16.index(utf16.startIndex, offsetBy: utf16Range.lowerBound)
        let upper = utf16.index(utf16.startIndex, offsetBy: utf16Range.upperBound)
        guard let startIndex = String.Index(lower, within: self),
              let endIndex = String.Index(upper, within: self) else {
            return nil
        }
        return String(self[startIndex..<endIndex])
    }
}

