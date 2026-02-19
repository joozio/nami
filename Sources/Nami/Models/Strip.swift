import Foundation
import CoreGraphics

/// A horizontal strip of columns on a single workspace
/// This is the core data structure for Nami's scrollable-tiling paradigm
final class Strip {
    /// Columns arranged left-to-right
    private(set) var columns: [Column] = []

    /// Current horizontal scroll offset (in points)
    /// Positive values scroll right (viewport moves left relative to content)
    var scrollOffset: CGFloat = 0

    /// Index of the currently focused column
    var focusedColumnIndex: Int = 0

    /// Gap between columns in points
    var columnGap: CGFloat = 10

    /// Padding from screen edges
    var edgePadding: CGFloat = 10

    /// The monitor this strip belongs to
    weak var monitor: Monitor?

    // MARK: - Computed Properties

    var isEmpty: Bool { columns.isEmpty }
    var count: Int { columns.count }

    var focusedColumn: Column? {
        guard focusedColumnIndex >= 0 && focusedColumnIndex < columns.count else { return nil }
        return columns[focusedColumnIndex]
    }

    var focusedWindow: NamiWindow? {
        focusedColumn?.focusedWindow
    }

    /// Total width of all columns plus gaps
    var totalContentWidth: CGFloat {
        guard !columns.isEmpty else { return 0 }
        let columnsWidth = columns.reduce(0) { $0 + $1.width }
        let gapsWidth = CGFloat(columns.count - 1) * columnGap
        return columnsWidth + gapsWidth + (edgePadding * 2)
    }

    /// All windows across all columns
    var allWindows: [NamiWindow] {
        columns.flatMap { $0.windows }
    }

    // MARK: - Column Management

    func addColumn(_ column: Column) {
        columns.append(column)
        reindexColumns()
    }

    func insertColumn(_ column: Column, at index: Int) {
        let safeIndex = max(0, min(index, columns.count))
        columns.insert(column, at: safeIndex)
        reindexColumns()
    }

    func insertColumn(_ column: Column, after existingColumn: Column) {
        if let index = columns.firstIndex(where: { $0.id == existingColumn.id }) {
            insertColumn(column, at: index + 1)
        } else {
            addColumn(column)
        }
    }

    func removeColumn(_ column: Column) -> Bool {
        guard let index = columns.firstIndex(where: { $0.id == column.id }) else { return false }
        columns.remove(at: index)
        reindexColumns()
        focusedColumnIndex = min(focusedColumnIndex, max(0, columns.count - 1))
        return true
    }

    func removeColumn(at index: Int) -> Column? {
        guard index >= 0 && index < columns.count else { return nil }
        let column = columns.remove(at: index)
        reindexColumns()
        focusedColumnIndex = min(focusedColumnIndex, max(0, columns.count - 1))
        return column
    }

    private func reindexColumns() {
        for (index, column) in columns.enumerated() {
            for window in column.windows {
                window.columnIndex = index
            }
        }
    }

    // MARK: - Window Operations

    /// Add a window in a new column after the focused column
    func addWindow(_ window: NamiWindow) {
        let newColumn = Column(window: window)
        if columns.isEmpty {
            addColumn(newColumn)
            focusedColumnIndex = 0
        } else {
            insertColumn(newColumn, at: focusedColumnIndex + 1)
            focusedColumnIndex += 1
        }
    }

    /// Add a window to the focused column's stack
    func stackWindow(_ window: NamiWindow) {
        if let column = focusedColumn {
            column.addWindow(window)
        } else {
            addWindow(window)
        }
    }

    func removeWindow(_ window: NamiWindow) -> Bool {
        for (columnIndex, column) in columns.enumerated() {
            if column.removeWindow(window) {
                // If column is now empty, remove it
                if column.isEmpty {
                    columns.remove(at: columnIndex)
                    reindexColumns()
                    focusedColumnIndex = min(focusedColumnIndex, max(0, columns.count - 1))
                }
                return true
            }
        }
        return false
    }

    func findColumn(containing window: NamiWindow) -> Column? {
        columns.first { $0.windows.contains(window) }
    }

    func findColumnIndex(containing window: NamiWindow) -> Int? {
        columns.firstIndex { $0.windows.contains(window) }
    }

    // MARK: - Focus Navigation

    func focusLeft() -> Bool {
        guard focusedColumnIndex > 0 else { return false }
        focusedColumnIndex -= 1
        return true
    }

    func focusRight() -> Bool {
        guard focusedColumnIndex < columns.count - 1 else { return false }
        focusedColumnIndex += 1
        return true
    }

    func focusUp() -> Bool {
        focusedColumn?.focusUp() ?? false
    }

    func focusDown() -> Bool {
        focusedColumn?.focusDown() ?? false
    }

    func focusWindow(_ window: NamiWindow) {
        for (columnIndex, column) in columns.enumerated() {
            if let stackIndex = column.windows.firstIndex(of: window) {
                focusedColumnIndex = columnIndex
                column.focusedStackIndex = stackIndex
                return
            }
        }
    }

    // MARK: - Column Movement

    func moveColumnLeft() -> Bool {
        guard focusedColumnIndex > 0 else { return false }
        columns.swapAt(focusedColumnIndex, focusedColumnIndex - 1)
        focusedColumnIndex -= 1
        reindexColumns()
        return true
    }

    func moveColumnRight() -> Bool {
        guard focusedColumnIndex < columns.count - 1 else { return false }
        columns.swapAt(focusedColumnIndex, focusedColumnIndex + 1)
        focusedColumnIndex += 1
        reindexColumns()
        return true
    }

    // MARK: - Layout Calculation

    /// Calculate the X position for a column given current scroll offset
    func xPosition(forColumnAt index: Int) -> CGFloat {
        guard index >= 0 && index < columns.count else { return 0 }

        var x = edgePadding - scrollOffset
        for i in 0..<index {
            x += columns[i].width + columnGap
        }
        return x
    }

    /// Calculate frame for a window within the monitor's visible area
    func calculateWindowFrame(for window: NamiWindow, in visibleFrame: CGRect) -> CGRect {
        guard let columnIndex = findColumnIndex(containing: window),
              let column = columns[safe: columnIndex] else {
            return window.frame
        }

        let x = xPosition(forColumnAt: columnIndex)
        let columnHeight = visibleFrame.height - (edgePadding * 2)

        // For stacked windows, divide height equally
        let stackCount = column.count
        let windowHeight = stackCount > 1
            ? (columnHeight - CGFloat(stackCount - 1) * columnGap) / CGFloat(stackCount)
            : columnHeight

        let stackOffset = CGFloat(window.stackIndex) * (windowHeight + columnGap)

        return CGRect(
            x: visibleFrame.minX + x,
            y: visibleFrame.minY + edgePadding + stackOffset,
            width: column.width,
            height: windowHeight
        )
    }

    /// Center viewport on the focused column
    func centerOnFocusedColumn(viewportWidth: CGFloat) {
        guard let column = focusedColumn else { return }

        let columnX = xPosition(forColumnAt: focusedColumnIndex) + scrollOffset
        let columnCenter = columnX + column.width / 2
        let viewportCenter = viewportWidth / 2

        scrollOffset = columnCenter - viewportCenter
        clampScrollOffset(viewportWidth: viewportWidth)
    }

    /// Ensure focused column is visible (but don't center)
    func ensureFocusedColumnVisible(viewportWidth: CGFloat) {
        guard let column = focusedColumn else { return }

        let columnLeft = xPosition(forColumnAt: focusedColumnIndex)
        let columnRight = columnLeft + column.width

        // If column is off the left edge, scroll to show it
        if columnLeft < edgePadding {
            scrollOffset += columnLeft - edgePadding
        }
        // If column is off the right edge, scroll to show it
        else if columnRight > viewportWidth - edgePadding {
            scrollOffset += columnRight - (viewportWidth - edgePadding)
        }

        clampScrollOffset(viewportWidth: viewportWidth)
    }

    private func clampScrollOffset(viewportWidth: CGFloat) {
        let maxScroll = max(0, totalContentWidth - viewportWidth)
        scrollOffset = max(0, min(scrollOffset, maxScroll))
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Strip: CustomDebugStringConvertible {
    var debugDescription: String {
        let cols = columns.map { "\($0.count)w" }.joined(separator: ", ")
        return "Strip(columns: [\(cols)], scroll: \(scrollOffset), focused: \(focusedColumnIndex))"
    }
}
