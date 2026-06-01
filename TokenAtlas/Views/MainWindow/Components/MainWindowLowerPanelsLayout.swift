import SwiftUI

enum MainWindowLowerPanelsWidthPolicy: Equatable {
    case leadingFixed(width: CGFloat, trailingMinimumWidth: CGFloat)
    case trailingFixed(width: CGFloat, leadingMinimumWidth: CGFloat)

    var horizontalMinimumWidth: CGFloat {
        switch self {
        case let .leadingFixed(width, trailingMinimumWidth):
            width + trailingMinimumWidth
        case let .trailingFixed(width, leadingMinimumWidth):
            width + leadingMinimumWidth
        }
    }

    func columnWidths(for availableWidth: CGFloat, spacing: CGFloat) -> (leading: CGFloat, trailing: CGFloat)? {
        guard availableWidth >= horizontalMinimumWidth + spacing else { return nil }

        switch self {
        case let .leadingFixed(width, trailingMinimumWidth):
            let trailing = max(trailingMinimumWidth, availableWidth - width - spacing)
            return (width, trailing)
        case let .trailingFixed(width, leadingMinimumWidth):
            let leading = max(leadingMinimumWidth, availableWidth - width - spacing)
            return (leading, width)
        }
    }
}

struct MainWindowLowerPanelsLayout: Layout {
    let widthPolicy: MainWindowLowerPanelsWidthPolicy
    let spacing: CGFloat

    private var horizontalMinimumWidth: CGFloat {
        widthPolicy.horizontalMinimumWidth + spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }

        let availableWidth = proposal.width ?? horizontalMinimumWidth
        if let columns = widthPolicy.columnWidths(for: availableWidth, spacing: spacing) {
            let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: columns.leading, height: nil))
            let trailingSize = subviews[1].sizeThatFits(ProposedViewSize(width: columns.trailing, height: nil))
            return CGSize(width: availableWidth, height: max(leadingSize.height, trailingSize.height))
        }

        let stackedWidth = max(0, availableWidth)
        let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: stackedWidth, height: nil))
        let trailingSize = subviews[1].sizeThatFits(ProposedViewSize(width: stackedWidth, height: nil))
        return CGSize(width: stackedWidth, height: leadingSize.height + spacing + trailingSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else { return }

        if let columns = widthPolicy.columnWidths(for: bounds.width, spacing: spacing) {
            let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: columns.leading, height: nil))
            let trailingSize = subviews[1].sizeThatFits(ProposedViewSize(width: columns.trailing, height: nil))
            let rowHeight = max(leadingSize.height, trailingSize.height)

            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.leading, height: rowHeight)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + columns.leading + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.trailing, height: rowHeight)
            )
        } else {
            let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + leadingSize.height + spacing),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}
