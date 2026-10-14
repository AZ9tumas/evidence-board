import CoreGraphics
import Foundation

/// A uniform grid over world space that answers "which cards are near this rect?" without
/// looking at every card. Used for viewport culling and hit testing.
struct SpatialGrid {
    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    /// Items covering more cells than this go in a list that every query checks instead.
    private static let maximumCellsPerItem = 4096

    let cellSize: CGFloat
    private var cells: [Cell: Set<UUID>] = [:]
    private var oversized: Set<UUID> = []
    private(set) var rects: [UUID: CGRect] = [:]

    init(cellSize: CGFloat = 512) {
        self.cellSize = cellSize
    }

    var count: Int { rects.count }

    mutating func insert(_ id: UUID, rect: CGRect) {
        remove(id)
        rects[id] = rect
        guard let range = cellRange(for: rect), range.count <= Self.maximumCellsPerItem else {
            oversized.insert(id)
            return
        }
        for cell in range.cells { cells[cell, default: []].insert(id) }
    }

    mutating func remove(_ id: UUID) {
        guard let rect = rects.removeValue(forKey: id) else { return }
        if oversized.remove(id) != nil { return }
        guard let range = cellRange(for: rect) else { return }
        for cell in range.cells {
            cells[cell]?.remove(id)
            if cells[cell]?.isEmpty == true { cells[cell] = nil }
        }
    }

    /// Items whose rect intersects `rect`.
    func query(_ rect: CGRect) -> Set<UUID> {
        var result = oversized.filter { rects[$0]?.intersects(rect) == true }
        guard let range = cellRange(for: rect) else { return result }
        if range.count > cells.count {
            // Zoomed far out: scanning the occupied cells is cheaper than visiting empty ones.
            for (cell, ids) in cells where range.contains(cell) {
                for id in ids where rects[id]?.intersects(rect) == true { result.insert(id) }
            }
        } else {
            for cell in range.cells {
                for id in cells[cell] ?? [] where rects[id]?.intersects(rect) == true { result.insert(id) }
            }
        }
        return result
    }

    /// Items whose rect contains `point`.
    func query(_ point: CGPoint) -> Set<UUID> {
        query(CGRect(x: point.x, y: point.y, width: 0, height: 0).insetBy(dx: -0.5, dy: -0.5))
    }

    private struct CellRange {
        let minX: Int, maxX: Int, minY: Int, maxY: Int

        var count: Int { (maxX - minX + 1) * (maxY - minY + 1) }

        var cells: [Cell] {
            (minY...maxY).flatMap { y in (minX...maxX).map { Cell(x: $0, y: y) } }
        }

        func contains(_ cell: Cell) -> Bool {
            (minX...maxX).contains(cell.x) && (minY...maxY).contains(cell.y)
        }
    }

    private func cellRange(for rect: CGRect) -> CellRange? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite else { return nil }
        let limit = CGFloat(Int32.max)
        func cell(_ value: CGFloat) -> Int { Int(min(max((value / cellSize).rounded(.down), -limit), limit)) }
        return CellRange(minX: cell(rect.minX), maxX: cell(rect.maxX), minY: cell(rect.minY), maxY: cell(rect.maxY))
    }
}
