import Foundation

/// A column in the strip, containing one or more stacked windows
final class Column: Identifiable {
    let id = UUID()

    /// Windows stacked vertically in this column (bottom to top)
    private(set) var windows: [NamiWindow] = []

    /// The width of this column in points
    var width: CGFloat

    /// Index of the focused window within the stack
    var focusedStackIndex: Int = 0

    /// Default column width
    static let defaultWidth: CGFloat = 800

    /// Minimum column width
    static let minimumWidth: CGFloat = 400

    /// Maximum column width
    static let maximumWidth: CGFloat = 2000

    init(width: CGFloat = Column.defaultWidth) {
        self.width = width
    }

    init(window: NamiWindow, width: CGFloat = Column.defaultWidth) {
        self.width = width
        addWindow(window)
    }

    // MARK: - Window Management

    var isEmpty: Bool { windows.isEmpty }
    var count: Int { windows.count }
    var focusedWindow: NamiWindow? {
        guard focusedStackIndex >= 0 && focusedStackIndex < windows.count else { return nil }
        return windows[focusedStackIndex]
    }

    func addWindow(_ window: NamiWindow) {
        window.stackIndex = windows.count
        windows.append(window)
        focusedStackIndex = window.stackIndex
    }

    func insertWindow(_ window: NamiWindow, at index: Int) {
        let safeIndex = max(0, min(index, windows.count))
        windows.insert(window, at: safeIndex)
        reindexWindows()
        focusedStackIndex = safeIndex
    }

    func removeWindow(_ window: NamiWindow) -> Bool {
        guard let index = windows.firstIndex(of: window) else { return false }
        windows.remove(at: index)
        reindexWindows()
        focusedStackIndex = min(focusedStackIndex, max(0, windows.count - 1))
        return true
    }

    func removeWindow(at index: Int) -> NamiWindow? {
        guard index >= 0 && index < windows.count else { return nil }
        let window = windows.remove(at: index)
        reindexWindows()
        focusedStackIndex = min(focusedStackIndex, max(0, windows.count - 1))
        return window
    }

    private func reindexWindows() {
        for (index, window) in windows.enumerated() {
            window.stackIndex = index
        }
    }

    // MARK: - Focus Navigation

    func focusUp() -> Bool {
        guard focusedStackIndex > 0 else { return false }
        focusedStackIndex -= 1
        return true
    }

    func focusDown() -> Bool {
        guard focusedStackIndex < windows.count - 1 else { return false }
        focusedStackIndex += 1
        return true
    }

    // MARK: - Width Adjustment

    func increaseWidth(by amount: CGFloat = 50) {
        width = min(width + amount, Column.maximumWidth)
    }

    func decreaseWidth(by amount: CGFloat = 50) {
        width = max(width - amount, Column.minimumWidth)
    }

    func setWidth(_ newWidth: CGFloat) {
        width = max(Column.minimumWidth, min(newWidth, Column.maximumWidth))
    }
}

extension Column: CustomDebugStringConvertible {
    var debugDescription: String {
        let windowDescs = windows.map { $0.title }.joined(separator: ", ")
        return "Column(width: \(width), windows: [\(windowDescs)])"
    }
}
