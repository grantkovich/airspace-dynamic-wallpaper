import CoreGraphics
import Foundation

public enum LabelSlot: Int, CaseIterable, Sendable { case right, left, above, below }

public struct LabelRequest: Sendable {
    public var id: String
    public var anchor: CGPoint
    public var size: CGSize
    /// Lower is more important.
    public var priority: Double
    /// Clearance from the anchor to the label.
    public var gap: CGFloat

    public init(id: String, anchor: CGPoint, size: CGSize, priority: Double, gap: CGFloat = 7) {
        self.id = id
        self.anchor = anchor
        self.size = size
        self.priority = priority
        self.gap = gap
    }

    func rect(_ slot: LabelSlot) -> CGRect {
        switch slot {
        case .right: CGRect(x: anchor.x + gap, y: anchor.y - size.height / 2, width: size.width, height: size.height)
        case .left: CGRect(x: anchor.x - gap - size.width, y: anchor.y - size.height / 2, width: size.width, height: size.height)
        case .above: CGRect(x: anchor.x - size.width / 2, y: anchor.y - gap - size.height, width: size.width, height: size.height)
        case .below: CGRect(x: anchor.x - size.width / 2, y: anchor.y + gap, width: size.width, height: size.height)
        }
    }
}

public struct PlacedLabel: Sendable, Equatable {
    public var id: String
    public var rect: CGRect
    public var slot: LabelSlot
}

/// Greedy label placement: most important first, four candidate slots each, no overlaps with
/// other labels, other aircraft, or obstacles. Labels that don't fit are dropped.
public enum LabelLayout {
    public static func layout(_ requests: [LabelRequest], obstacles: [CGRect], bounds: CGRect,
                              previous: [String: LabelSlot], glyphRadius: CGFloat = 4) -> [PlacedLabel] {
        let sorted = requests.sorted { $0.priority < $1.priority }
        let glyphs = requests.map {
            (id: $0.id, rect: CGRect(x: $0.anchor.x - glyphRadius, y: $0.anchor.y - glyphRadius,
                                     width: glyphRadius * 2, height: glyphRadius * 2))
        }
        var placed: [PlacedLabel] = []
        placed.reserveCapacity(sorted.count)

        for req in sorted {
            var order = LabelSlot.allCases
            if let prev = previous[req.id], let i = order.firstIndex(of: prev) {
                order.remove(at: i)
                order.insert(prev, at: 0)
            }
            for slot in order {
                let r = req.rect(slot)
                guard bounds.contains(r),
                      !obstacles.contains(where: { $0.intersects(r) }),
                      !placed.contains(where: { $0.rect.intersects(r) }),
                      !glyphs.contains(where: { $0.id != req.id && $0.rect.intersects(r) }) else { continue }
                placed.append(PlacedLabel(id: req.id, rect: r, slot: slot))
                break
            }
        }
        return placed
    }
}
