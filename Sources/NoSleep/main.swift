import AppKit
import Foundation
import IOKit.pwr_mgt

final class PowerAssertionManager {
    private var systemAssertionID = IOPMAssertionID(0)
    private var displayAssertionID = IOPMAssertionID(0)

    var isEnabled: Bool {
        systemAssertionID != 0 || displayAssertionID != 0
    }

    func enable() throws {
        guard !isEnabled else { return }

        let reason = "NoSleep 正在保持 Mac 清醒" as CFString

        var systemID = IOPMAssertionID(0)
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )

        guard systemResult == kIOReturnSuccess else {
            throw AppError.powerAssertionFailed(systemResult)
        }

        var displayID = IOPMAssertionID(0)
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayID
        )

        guard displayResult == kIOReturnSuccess else {
            IOPMAssertionRelease(systemID)
            throw AppError.powerAssertionFailed(displayResult)
        }

        systemAssertionID = systemID
        displayAssertionID = displayID
    }

    func disable() {
        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }

        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
    }
}

final class LidModeManager {
    private let privilegeManager = PrivilegeManager()
    private let initialState: Bool
    private(set) var isEnabled: Bool

    init() {
        initialState = Self.readSystemDisableSleepState()
        isEnabled = initialState
    }

    func enable() throws {
        guard !isEnabled else { return }
        try runPrivilegedPMSet(disableSleep: true)
        isEnabled = true
    }

    func disable() throws {
        guard isEnabled else { return }
        try runPrivilegedPMSet(disableSleep: false)
        isEnabled = false
    }

    func restoreInitialState() {
        guard isEnabled != initialState else { return }
        try? runPrivilegedPMSet(disableSleep: initialState)
        isEnabled = initialState
    }

    func installPasswordlessPermission() throws {
        try privilegeManager.installPasswordlessPermission()
    }

    func hasPasswordlessPermission() -> Bool {
        privilegeManager.hasPasswordlessPermission()
    }

    private func runPrivilegedPMSet(disableSleep: Bool) throws {
        let value = disableSleep ? "1" : "0"
        try privilegeManager.runTool(
            at: "/usr/bin/pmset",
            arguments: ["-a", "disablesleep", value]
        )
    }

    private static func readSystemDisableSleepState() -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return false
        }

        return output
            .split(separator: "\n")
            .contains { line in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                return parts.count >= 2 && parts[0] == "disablesleep" && parts[1] == "1"
            }
    }
}

enum AppError: LocalizedError {
    case unsupportedUserName(String)
    case powerAssertionFailed(IOReturn)
    case privilegedCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedUserName(let userName):
            return "当前用户名「\(userName)」包含 sudoers 规则不支持的字符。"
        case .powerAssertionFailed(let code):
            return "无法创建 macOS 防休眠请求。错误代码：\(code)。"
        case .privilegedCommandFailed(let message):
            return "系统设置没有完成。\(message)"
        }
    }
}

final class PrivilegeManager {
    func hasPasswordlessPermission() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "-l", "/usr/bin/pmset"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func runTool(at path: String, arguments: [String]) throws {
        if runWithoutPassword(path: path, arguments: arguments) {
            return
        }

        try runWithAdministratorPrompt(path: path, arguments: arguments)
    }

    func installPasswordlessPermission() throws {
        let userName = NSUserName()
        guard userName.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw AppError.unsupportedUserName(userName)
        }

        let sudoersLine = "\(userName) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let command = """
        tmp="$(/usr/bin/mktemp)" && \
        /usr/bin/printf '%s\\n' \(sudoersLine.shellQuoted) > "$tmp" && \
        /usr/sbin/visudo -cf "$tmp" && \
        /bin/mkdir -p /etc/sudoers.d && \
        /usr/bin/install -o root -g wheel -m 0440 "$tmp" /etc/sudoers.d/nosleep-pmset && \
        /bin/rm -f "$tmp"
        """

        try runShellWithAdministratorPrompt(command)
    }

    private func runWithoutPassword(path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runWithAdministratorPrompt(path: String, arguments: [String]) throws {
        let command = ([path] + arguments).map(\.shellQuoted).joined(separator: " ")
        try runShellWithAdministratorPrompt(command)
    }

    private func runShellWithAdministratorPrompt(_ command: String) throws {
        let script = "do shell script \(command.appleScriptQuoted) with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw AppError.privilegedCommandFailed("无法准备管理员授权窗口。")
        }

        appleScript.executeAndReturnError(&error)

        if let error {
            throw AppError.privilegedCommandFailed(error.description)
        }
    }
}

extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum AppMode {
        case normal
        case awake
        case lidClosed
    }

    private static let permissionGuideCompletedKey = "permissionGuideCompleted"

    private let assertionManager = PowerAssertionManager()
    private let lidModeManager = LidModeManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let normalModeItem = NSMenuItem()
    private let awakeModeItem = NSMenuItem()
    private let lidModeItem = NSMenuItem()
    private let statusItemText = NSMenuItem()
    private var passwordlessPermissionInstalled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        rebuildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showPasswordlessPermissionGuideIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        assertionManager.disable()
        lidModeManager.restoreInitialState()
    }

    private func configureStatusItem() {
        statusItem.button?.image = currentStatusImage()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = ""
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusItemText.title = currentStatusText()
        statusItemText.isEnabled = false
        menu.addItem(statusItemText)
        menu.addItem(.separator())

        configureModeItem(
            normalModeItem,
            title: "正常休眠",
            subtitle: "不干预系统行为，自动进入休眠",
            mode: .normal,
            action: #selector(selectNormalMode)
        )
        menu.addItem(normalModeItem)

        configureModeItem(
            awakeModeItem,
            title: "保持清醒",
            subtitle: "防止系统休眠，屏幕常亮",
            mode: .awake,
            action: #selector(selectAwakeMode)
        )
        menu.addItem(awakeModeItem)

        configureModeItem(
            lidModeItem,
            title: "合盖继续工作",
            subtitle: "合上盖子，程序继续运行",
            mode: .lidClosed,
            action: #selector(selectLidMode)
        )
        menu.addItem(lidModeItem)

        normalModeItem.state = currentMode() == .normal ? .on : .off
        awakeModeItem.state = currentMode() == .awake ? .on : .off
        lidModeItem.state = lidModeManager.isEnabled ? .on : .off

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "关于合盖模式",
            action: #selector(showLidModeInfo),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.image = currentStatusImage()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuItems()
    }

    private func refreshMenuItems() {
        statusItemText.title = currentStatusText()
        normalModeItem.state = currentMode() == .normal ? .on : .off
        awakeModeItem.state = currentMode() == .awake ? .on : .off
        lidModeItem.state = currentMode() == .lidClosed ? .on : .off
        statusItem.button?.image = currentStatusImage()
        statusItem.button?.needsDisplay = true
    }

    private func configureModeItem(
        _ item: NSMenuItem,
        title: String,
        subtitle: String,
        mode: AppMode,
        action: Selector
    ) {
        item.attributedTitle = modeTitle(title: title, subtitle: subtitle)
        item.image = menuStateIcon(for: mode)
        item.target = self
        item.action = action
    }

    private func modeTitle(title: String, subtitle: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.append(NSAttributedString(
            string: "\n\(subtitle)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        return result
    }

    private func menuStateIcon(for mode: AppMode) -> NSImage {
        let size = NSSize(width: 30, height: 30)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 7, yRadius: 7).fill()

        let iconRect = NSRect(x: 7, y: 7, width: 16, height: 16)
        switch mode {
        case .normal:
            NSColor.white.setFill()
            NSBezierPath(ovalIn: iconRect).fill()
            NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
            NSBezierPath(ovalIn: iconRect.offsetBy(dx: 6, dy: 3)).fill()
        case .awake:
            NSColor.white.setStroke()
            let path = NSBezierPath(ovalIn: iconRect.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 2.6
            path.stroke()
        case .lidClosed:
            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: iconRect.insetBy(dx: 1, dy: 1)).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func currentStatusImage() -> NSImage? {
        let symbolName: String

        if lidModeManager.isEnabled {
            symbolName = "circle.fill"
        } else if assertionManager.isEnabled {
            symbolName = "circle"
        } else {
            symbolName = "moon.zzz.fill"
        }

        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "NoSleep")
    }

    private func currentStatusText() -> String {
        switch currentMode() {
        case .normal:
            return "正常休眠"
        case .awake:
            return "保持清醒"
        case .lidClosed:
            return "合盖继续工作"
        }
    }

    private func currentMode() -> AppMode {
        if lidModeManager.isEnabled {
            return .lidClosed
        }

        if assertionManager.isEnabled {
            return .awake
        }

        return .normal
    }

    @objc private func selectNormalMode() {
        do {
            try lidModeManager.disable()
            assertionManager.disable()
            refreshMenuItems()
        } catch {
            showError(error)
            refreshMenuItems()
        }
    }

    @objc private func selectAwakeMode() {
        do {
            try lidModeManager.disable()
            try assertionManager.enable()
            refreshMenuItems()
        } catch {
            showError(error)
            refreshMenuItems()
        }
    }

    @objc private func selectLidMode() {
        do {
            try assertionManager.enable()
            try lidModeManager.enable()
            refreshMenuItems()
        } catch {
            showError(error)
            refreshMenuItems()
        }
    }

    @objc private func showLidModeInfo() {
        let alert = NSAlert()
        alert.messageText = "合盖后继续工作"
        alert.informativeText = """
        此模式会修改 macOS 的系统电源设置，让 Codex 等后台任务在 MacBook 合盖后继续运行。

        第一次打开 NoSleep 时会引导你安装免密授权。安装成功后，NoSleep 之后可以免密开启、关闭和退出时恢复合盖设置。

        退出 NoSleep 时，会尝试恢复应用启动前的休眠状态。为了稳定和安全，建议插电使用，并保持散热良好。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "NoSleep 无法修改这个设置"
        alert.runModal()
    }

    private func showPasswordlessPermissionGuideIfNeeded() {
        if lidModeManager.hasPasswordlessPermission() {
            passwordlessPermissionInstalled = true
            UserDefaults.standard.set(true, forKey: Self.permissionGuideCompletedKey)
            refreshMenuItems()
            return
        }

        guard !UserDefaults.standard.bool(forKey: Self.permissionGuideCompletedKey) else {
            refreshMenuItems()
            return
        }

        let alert = NSAlert()
        alert.messageText = "完成 NoSleep 初始设置"
        alert.informativeText = """
        NoSleep 需要安装一次免密授权，之后才能在开启、关闭和退出恢复“合盖后继续工作”时不反复输入管理员密码。

        授权范围只限当前用户执行：
        /usr/bin/pmset -a disablesleep 0
        /usr/bin/pmset -a disablesleep 1
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "开始授权")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            installPasswordlessPermissionFromGuide()
        }
    }

    private func installPasswordlessPermissionFromGuide() {
        do {
            try lidModeManager.installPasswordlessPermission()
            passwordlessPermissionInstalled = true
            UserDefaults.standard.set(true, forKey: Self.permissionGuideCompletedKey)
            refreshMenuItems()
            let alert = NSAlert()
            alert.messageText = "NoSleep 已准备好"
            alert.informativeText = "之后 NoSleep 开启、关闭和恢复合盖设置时，不需要再输入管理员密码。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
        } catch {
            passwordlessPermissionInstalled = false
            showError(error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
