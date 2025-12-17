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
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let sizeProposal = ProposedViewSize(width: maxWidth, height: nil)
            let size = subview.sizeThatFits(sizeProposal)

            if currentX > bounds.minX, currentX + size.width > bounds.minX + maxWidth {
                currentX = bounds.minX
                currentY += lineHeight
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: sizeProposal
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
