import AppKit
import ApplicationServices
import NamiBridge

// MARK: - AXUIElement Extensions

extension AXUIElement {

    // MARK: - Element Creation

    /// Create an AXUIElement for the system-wide element
    static var systemWide: AXUIElement {
        AXUIElementCreateSystemWide()
    }

    /// Create an AXUIElement for an application
    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    // MARK: - Attribute Getters

    /// Get an attribute value
    func attribute<T>(_ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    /// Get a CGPoint attribute
    func pointAttribute(_ attribute: String) -> CGPoint? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        // Safely extract point without type validation warnings
        var point = CGPoint.zero
        if AXValueGetValue(axValue as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    /// Get a CGSize attribute
    func sizeAttribute(_ attribute: String) -> CGSize? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        // Safely extract size without type validation warnings
        var size = CGSize.zero
        if AXValueGetValue(axValue as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    /// Get a Bool attribute
    func boolAttribute(_ attribute: String) -> Bool {
        let value: CFBoolean? = self.attribute(attribute)
        return value.map { CFBooleanGetValue($0) } ?? false
    }

    // MARK: - Attribute Setters

    /// Set an attribute value
    @discardableResult
    func setAttribute(_ attribute: String, value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    /// Set a CGPoint attribute
    @discardableResult
    func setPointAttribute(_ attribute: String, point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return setAttribute(attribute, value: value)
    }

    /// Set a CGSize attribute
    @discardableResult
    func setSizeAttribute(_ attribute: String, size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return setAttribute(attribute, value: value)
    }

    // MARK: - Common Window Properties

    var title: String? {
        attribute(kAXTitleAttribute)
    }

    var role: String? {
        attribute(kAXRoleAttribute)
    }

    var subrole: String? {
        attribute(kAXSubroleAttribute)
    }

    var position: CGPoint? {
        pointAttribute(kAXPositionAttribute)
    }

    var size: CGSize? {
        sizeAttribute(kAXSizeAttribute)
    }

    var frame: CGRect? {
        guard let position = position, let size = size else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isMinimized: Bool {
        boolAttribute(kAXMinimizedAttribute)
    }

    var isFullscreen: Bool {
        boolAttribute("AXFullScreen")
    }

    var isFocused: Bool {
        boolAttribute(kAXFocusedAttribute)
    }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    // MARK: - Window Operations

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        setPointAttribute(kAXPositionAttribute, point: point)
    }

    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        setSizeAttribute(kAXSizeAttribute, size: size)
    }

    @discardableResult
    func setMinimized(_ minimized: Bool) -> Bool {
        setAttribute(kAXMinimizedAttribute, value: minimized as CFBoolean)
    }

    func raise() {
        performAction(kAXRaiseAction)
    }

    func close() {
        // Find the close button and press it
        if let closeButton: AXUIElement = attribute(kAXCloseButtonAttribute) {
            closeButton.performAction(kAXPressAction)
        }
    }

    @discardableResult
    func performAction(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    // MARK: - Window Enumeration

    var windows: [AXUIElement] {
        attribute(kAXWindowsAttribute) ?? []
    }

    var focusedWindow: AXUIElement? {
        attribute(kAXFocusedWindowAttribute)
    }

    // MARK: - CGWindowID Bridge (Private API)

    /// Get the CGWindowID for this window element
    /// Uses the private _AXUIElementGetWindow API
    var cgWindowID: CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(self, &windowID)
        return result == .success ? windowID : nil
    }

    // MARK: - Window Validation

    /// Check if this is a standard, manageable window
    var isStandardWindow: Bool {
        guard let role = role else { return false }

        // Must be a window
        guard role == kAXWindowRole else { return false }

        // Check subrole - we want standard windows, not dialogs, sheets, etc.
        let subrole = self.subrole
        let validSubroles: Set<String?> = [kAXStandardWindowSubrole, nil]
        guard validSubroles.contains(subrole) else { return false }

        // Must have a size (not zero)
        guard let size = size, size.width > 0, size.height > 0 else { return false }

        return true
    }

    /// Check if window should be managed by Nami
    var isManageable: Bool {
        guard isStandardWindow else { return false }
        guard !isMinimized else { return false }

        // Minimum size threshold
        guard let size = size, size.width >= 100, size.height >= 100 else { return false }

        return true
    }
}

// MARK: - Permission Checking

enum AccessibilityPermission {
    /// Check if accessibility permission is granted
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user for accessibility permission
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Check and prompt if needed, returns current status
    @discardableResult
    static func checkAndPrompt() -> Bool {
        if isGranted { return true }
        requestAccess()
        return false
    }
}
