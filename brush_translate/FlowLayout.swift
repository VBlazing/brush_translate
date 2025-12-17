import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 0) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let sizeProposal = maxWidth.isFinite ? ProposedViewSize(width: maxWidth, height: nil) : .unspecified
            let size = subview.sizeThatFits(sizeProposal)
            if currentX > 0, currentX + size.width > maxWidth {
                maxLineWidth = max(maxLineWidth, currentX)
                currentX = 0
                currentY += lineHeight
                lineHeight = 0
            }

            if index > 0, currentX > 0 {
                currentX += spacing
            }
            currentX += size.width
            lineHeight = max(lineHeight, size.height)
        }

        maxLineWidth = max(maxLineWidth, currentX)
        let totalHeight = currentY + lineHeight
        let finalWidth = proposal.width ?? maxLineWidth
        return CGSize(width: finalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        let sizeProposal = ProposedViewSize(width: maxWidth, height: nil)

        struct Line {
            var items: [(LayoutSubview, CGSize)] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        var lines: [Line] = []
        var currentLine = Line()

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(sizeProposal)
            let itemWidth = size.width + ((index == 0 || currentLine.items.isEmpty) ? 0 : spacing)

            if !currentLine.items.isEmpty, currentLine.width + itemWidth > maxWidth {
                lines.append(currentLine)
                currentLine = Line()
            }

            let addSpacing = currentLine.items.isEmpty ? 0 : spacing
            currentLine.items.append((subview, size))
            currentLine.width += size.width + addSpacing
            currentLine.height = max(currentLine.height, size.height)
        }

        if !currentLine.items.isEmpty {
            lines.append(currentLine)
        }

        var currentY: CGFloat = bounds.minY
        for line in lines {
            var currentX = bounds.minX + max(0, (maxWidth - line.width) / 2)
            for (index, item) in line.items.enumerated() {
                let (subview, size) = item
                if index > 0 {
                    currentX += spacing
                }
                subview.place(
                    at: CGPoint(x: currentX, y: currentY),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                currentX += size.width
            }
            currentY += line.height
        }
    }
}
