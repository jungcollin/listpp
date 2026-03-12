import AppKit
import Foundation

struct PortEntry: Hashable {
    let command: String
    let pid: Int
    let user: String
    let port: Int
    let serviceName: String?
    let endpoints: [String]
    let commandLine: String?
}

enum EntrySortMode {
    case newest
    case port

    var segmentIndex: Int {
        switch self {
        case .newest: return 0
        case .port: return 1
        }
    }

    init?(segmentIndex: Int) {
        switch segmentIndex {
        case 0: self = .newest
        case 1: self = .port
        default: return nil
        }
    }
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        } catch {
            return nil
        }
    }

    static func launchDetached(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = nil
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

final class ServiceCatalog {
    private let commandHints: [String: String] = [
        "postgres": "postgresql",
        "postmaster": "postgresql",
        "mysqld": "mysql",
        "redis-server": "redis",
        "mongod": "mongodb",
        "nginx": "http",
        "httpd": "http",
        "apache2": "http",
        "sshd": "ssh",
        "docker-proxy": "docker"
    ]
    private let tcpPortMap: [Int: String]

    init(servicesFilePath: String = "/etc/services") {
        self.tcpPortMap = ServiceCatalog.loadTCPServices(from: servicesFilePath)
    }

    func resolveServiceName(port: Int, command: String) -> String? {
        let normalized = command.lowercased()
        if let hinted = commandHints[normalized] {
            return hinted
        }
        return tcpPortMap[port]
    }

    private static func loadTCPServices(from path: String) -> [Int: String] {
        guard let file = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var map: [Int: String] = [:]

        for rawLine in file.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let withoutComment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let tokens = withoutComment.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else {
                continue
            }

            let service = String(tokens[0])
            let portProto = tokens[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard portProto.count == 2 else {
                continue
            }
            guard portProto[1].lowercased() == "tcp" else {
                continue
            }
            guard let port = Int(portProto[0]) else {
                continue
            }

            if map[port] == nil {
                map[port] = service
            }
        }

        return map
    }
}

final class PortScanner {
    private struct ProcessMetadata {
        let commandLine: String
        let elapsedSeconds: Int?
    }

    private struct RawPortRecord {
        let command: String
        let pid: Int
        let user: String
        let endpoint: String
        let port: Int
    }

    private struct PortGroupKey: Hashable {
        let command: String
        let pid: Int
        let user: String
        let port: Int
        let serviceName: String?
    }

    private let serviceCatalog = ServiceCatalog()

    func scanListeningTCPPorts(sortedBy sortMode: EntrySortMode) -> [PortEntry] {
        guard let result = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) else {
            return []
        }
        guard result.status == 0 else {
            return []
        }

        let lines = result.stdout.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else {
            return []
        }

        var grouped: [PortGroupKey: Set<String>] = [:]
        for line in lines.dropFirst() {
            guard let raw = parse(line: String(line)) else {
                continue
            }

            let serviceName = serviceCatalog.resolveServiceName(port: raw.port, command: raw.command)
            let key = PortGroupKey(
                command: raw.command,
                pid: raw.pid,
                user: raw.user,
                port: raw.port,
                serviceName: serviceName
            )

            grouped[key, default: []].insert(raw.endpoint)
        }

        let pids = Array(Set(grouped.keys.map(\.pid))).sorted()
        let processMetadata = fetchProcessMetadata(for: pids)

        let entries = grouped.map { key, endpoints in
            PortEntry(
                command: key.command,
                pid: key.pid,
                user: key.user,
                port: key.port,
                serviceName: key.serviceName,
                endpoints: endpoints.sorted(),
                commandLine: processMetadata[key.pid]?.commandLine
            )
        }

        switch sortMode {
        case .newest:
            return entries.sorted { lhs, rhs in
                let lhsElapsed = processMetadata[lhs.pid]?.elapsedSeconds ?? Int.max
                let rhsElapsed = processMetadata[rhs.pid]?.elapsedSeconds ?? Int.max
                if lhsElapsed != rhsElapsed { return lhsElapsed < rhsElapsed }
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                if lhs.command != rhs.command { return lhs.command < rhs.command }
                return lhs.pid < rhs.pid
            }
        case .port:
            return entries.sorted { lhs, rhs in
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                if lhs.command != rhs.command { return lhs.command < rhs.command }
                return lhs.pid < rhs.pid
            }
        }
    }

    private func parse(line: String) -> RawPortRecord? {
        let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard columns.count >= 10 else { return nil }
        guard let pid = Int(columns[1]) else { return nil }

        let command = String(columns[0])
        let user = String(columns[2])
        var nameField = columns[8...].joined(separator: " ")

        if nameField.hasPrefix("TCP ") {
            nameField.removeFirst(4)
        }
        if nameField.hasSuffix(" (LISTEN)") {
            nameField.removeLast(" (LISTEN)".count)
        }

        guard let colon = nameField.lastIndex(of: ":") else { return nil }
        guard colon < nameField.index(before: nameField.endIndex) else { return nil }
        let portString = nameField[nameField.index(after: colon)...]
        guard let port = Int(portString) else { return nil }

        return RawPortRecord(
            command: command,
            pid: pid,
            user: user,
            endpoint: nameField,
            port: port
        )
    }

    private func fetchProcessMetadata(for pids: [Int]) -> [Int: ProcessMetadata] {
        guard !pids.isEmpty else { return [:] }
        let pidArg = pids.map(String.init).joined(separator: ",")

        guard let result = Shell.run("/bin/ps", ["-ww", "-o", "pid=", "-o", "etime=", "-o", "command=", "-p", pidArg]) else {
            return [:]
        }
        guard result.status == 0 else {
            return [:]
        }

        var map: [Int: ProcessMetadata] = [:]

        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            let tokens = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= 2 else {
                continue
            }
            guard let pid = Int(tokens[0]) else {
                continue
            }
            let elapsedText = String(tokens[1])
            let commandLine = tokens.count == 3
                ? String(tokens[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            map[pid] = ProcessMetadata(
                commandLine: commandLine,
                elapsedSeconds: parseElapsedSeconds(elapsedText)
            )
        }

        return map
    }

    private func parseElapsedSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var days = 0
        var timePart = trimmed
        if let dashIndex = trimmed.firstIndex(of: "-") {
            let dayText = trimmed[..<dashIndex]
            guard let parsedDays = Int(dayText) else { return nil }
            days = parsedDays
            timePart = String(trimmed[trimmed.index(after: dashIndex)...])
        }

        let fields = timePart.split(separator: ":")
        guard fields.count == 2 || fields.count == 3 else { return nil }

        func parseField(_ value: Substring) -> Int? {
            let numberPart = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
            return Int(numberPart)
        }

        if fields.count == 2 {
            guard
                let minutes = parseField(fields[0]),
                let seconds = parseField(fields[1])
            else { return nil }
            return (days * 24 * 60 * 60) + (minutes * 60) + seconds
        }

        guard
            let hours = parseField(fields[0]),
            let minutes = parseField(fields[1]),
            let seconds = parseField(fields[2])
        else { return nil }

        return (days * 24 * 60 * 60) + (hours * 60 * 60) + (minutes * 60) + seconds
    }
}

final class MenuToggleRowView: NSView {
    private let titleLabel: NSTextField
    private let onClick: () -> Void

    init(title: String, onClick: @escaping () -> Void) {
        self.titleLabel = NSTextField(labelWithString: title)
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 24))

        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 340),
            heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let scanner = PortScanner()
    private var entries: [PortEntry] = []
    private var duplicatePorts = Set<Int>()
    private let collapsedLimit = 15
    private var isExpanded = false
    private var sortMode: EntrySortMode = .newest
    private var refreshTimer: Timer?

    private var visibleEntries: [PortEntry] {
        if isExpanded || entries.count <= collapsedLimit {
            return entries
        }
        return Array(entries.prefix(collapsedLimit))
    }

    func start() {
        configureStatusItem()
        refresh()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(handleRefreshTick),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.imagePosition = .imageOnly
        updateStatusItemAppearance()

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func handleRefreshTick() {
        refresh()
    }

    @objc private func handleRefreshNow() {
        refresh()
    }

    @objc private func handleSortModeChanged(_ sender: NSSegmentedControl) {
        guard let selectedMode = EntrySortMode(segmentIndex: sender.selectedSegment) else { return }
        guard selectedMode != sortMode else { return }
        sortMode = selectedMode
        refresh()
    }

    @objc private func handleToggleExpanded() {
        guard entries.count > collapsedLimit else { return }
        isExpanded.toggle()
        rebuildMenu()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    @objc private func handleTerminate(_ sender: NSMenuItem) {
        guard let pidNumber = sender.representedObject as? NSNumber else { return }
        let pid = pidNumber.intValue

        guard terminateProcess(pid: pid) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func handleRestart(_ sender: NSMenuItem) {
        guard let pidNumber = sender.representedObject as? NSNumber else { return }
        let pid = pidNumber.intValue
        guard let entry = entries.first(where: { $0.pid == pid }) else {
            showError(title: "Restart Failed", detail: "Target process was not found.")
            return
        }
        guard let commandLine = entry.commandLine, !commandLine.isEmpty else {
            showError(title: "Restart Failed", detail: "Command line is unavailable for relaunch.")
            return
        }

        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Restart this process?"
        confirmation.informativeText = """
        Sends SIGTERM to \(entry.command) (\(pid)) and relaunches with the same command line.
        Cmd: \(truncate(commandLine, maxLength: 180))
        """
        confirmation.addButton(withTitle: "Restart")
        confirmation.addButton(withTitle: "Cancel")

        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        guard terminateProcess(pid: pid) else { return }

        let relaunched = Shell.launchDetached("/bin/zsh", ["-lc", commandLine])
        guard relaunched else {
            showError(title: "Restart Failed", detail: "Failed to relaunch command.")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refresh()
        }
    }

    private func showError(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail.isEmpty ? "No additional details are available." : detail
        alert.runModal()
    }

    private func terminateProcess(pid: Int) -> Bool {
        guard let killResult = Shell.run("/bin/kill", ["-TERM", String(pid)]) else {
            showError(title: "Terminate Failed", detail: "Failed to execute kill command.")
            return false
        }

        guard killResult.status == 0 else {
            let detail = killResult.stderr.isEmpty ? killResult.stdout : killResult.stderr
            showError(title: "Terminate Failed", detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
            return false
        }

        return true
    }

    private func refresh() {
        entries = scanner.scanListeningTCPPorts(sortedBy: sortMode)
        duplicatePorts = findDuplicatePorts(in: entries)
        if entries.count <= collapsedLimit {
            isExpanded = false
        }
        rebuildMenu()
    }

    private func findDuplicatePorts(in entries: [PortEntry]) -> Set<Int> {
        var frequency: [Int: Int] = [:]
        for entry in entries {
            frequency[entry.port, default: 0] += 1
        }
        return Set(frequency.compactMap { port, count in
            count > 1 ? port : nil
        })
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(makeHeaderItem())
        menu.addItem(.separator())

        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No listening TCP ports.", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for entry in visibleEntries {
                menu.addItem(makePortItem(entry))
            }
        }

        if entries.count > collapsedLimit {
            menu.addItem(.separator())
            menu.addItem(makeExpandCollapseItem())
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateStatusItemAppearance()
    }

    private func makeHeaderItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 32))
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Listening TCP Ports (\(entries.count))")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let sortControl = NSSegmentedControl(labels: ["Newest", "Port"], trackingMode: .selectOne, target: self, action: #selector(handleSortModeChanged(_:)))
        sortControl.segmentStyle = .rounded
        sortControl.controlSize = .small
        sortControl.selectedSegment = sortMode.segmentIndex
        sortControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        sortControl.setContentHuggingPriority(.required, for: .horizontal)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(handleRefreshNow))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, spacer, sortControl, refreshButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 410),
            container.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        item.view = container
        return item
    }

    private func makeExpandCollapseItem() -> NSMenuItem {
        let item = NSMenuItem()
        let title = isExpanded ? "▲ Show less" : "▼ Show \(entries.count - collapsedLimit) more"
        item.view = MenuToggleRowView(title: title) { [weak self] in
            self?.handleToggleExpanded()
        }
        return item
    }

    private func makePortItem(_ entry: PortEntry) -> NSMenuItem {
        let title = plainEntryTitle(entry)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let isDuplicatePort = duplicatePorts.contains(entry.port)
        item.attributedTitle = styledEntryTitle(entry, duplicate: isDuplicatePort)
        let submenu = NSMenu()

        let serviceItem = NSMenuItem(title: "Service: \(entry.serviceName ?? "-")", action: nil, keyEquivalent: "")
        serviceItem.isEnabled = false
        submenu.addItem(serviceItem)

        let pidItem = NSMenuItem(title: "PID: \(entry.pid)", action: nil, keyEquivalent: "")
        pidItem.isEnabled = false
        submenu.addItem(pidItem)

        let ownerItem = NSMenuItem(title: "User: \(entry.user)", action: nil, keyEquivalent: "")
        ownerItem.isEnabled = false
        submenu.addItem(ownerItem)

        if let commandLine = entry.commandLine, !commandLine.isEmpty {
            let commandLineItem = NSMenuItem(
                title: "Cmd(end): \(tailPreview(commandLine, maxLength: 220))",
                action: nil,
                keyEquivalent: ""
            )
            commandLineItem.isEnabled = false
            submenu.addItem(commandLineItem)
        }

        submenu.addItem(.separator())

        let endpointsTitle = entry.endpoints.count == 1 ? "Endpoint" : "Endpoints (\(entry.endpoints.count))"
        let endpointsItem = NSMenuItem(title: endpointsTitle, action: nil, keyEquivalent: "")
        endpointsItem.isEnabled = false
        submenu.addItem(endpointsItem)

        for endpoint in entry.endpoints {
            let endpointItem = NSMenuItem(title: "- \(endpoint)", action: nil, keyEquivalent: "")
            endpointItem.isEnabled = false
            submenu.addItem(endpointItem)
        }

        submenu.addItem(.separator())

        let restartItem = NSMenuItem(title: "Restart Process", action: #selector(handleRestart(_:)), keyEquivalent: "")
        restartItem.target = self
        restartItem.representedObject = NSNumber(value: entry.pid)
        restartItem.isEnabled = entry.commandLine?.isEmpty == false
        submenu.addItem(restartItem)

        let terminateItem = NSMenuItem(title: "Terminate Process", action: #selector(handleTerminate(_:)), keyEquivalent: "")
        terminateItem.target = self
        terminateItem.representedObject = NSNumber(value: entry.pid)
        submenu.addItem(terminateItem)

        item.submenu = submenu
        return item
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.toolTip = "Listening TCP Ports: \(entries.count)"

        let symbolCandidates = ["ferry.fill", "ferry"]

        for symbolName in symbolCandidates {
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Port Status") {
                image.isTemplate = true
                button.image = image
                return
            }
        }

        button.image = makeFallbackFerryStatusImage()
    }

    private func makeFallbackFerryStatusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let symbol = "⛴︎"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = symbol.size(withAttributes: attributes)
        let point = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1
        )
        symbol.draw(at: point, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "..."
    }

    private func tailPreview(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxLength)
        return "..." + String(text[start...])
    }

    private func plainEntryTitle(_ entry: PortEntry) -> String {
        let segments = formattedSegments(for: entry, duplicate: duplicatePorts.contains(entry.port))
        return segments.map(\.text).joined(separator: segmentSeparator)
    }

    private func styledEntryTitle(_ entry: PortEntry, duplicate: Bool) -> NSAttributedString {
        let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: menuFontSize, weight: .regular)
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.quaternaryLabelColor
        ]
        let coloredSegments = formattedSegments(for: entry, duplicate: duplicate)

        let title = NSMutableAttributedString()
        for (index, segment) in coloredSegments.enumerated() {
            title.append(
                NSAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: segment.color
                    ]
                )
            )

            if index + 1 < coloredSegments.count {
                title.append(NSAttributedString(string: segmentSeparator, attributes: separatorAttributes))
            }
        }

        return title
    }

    private struct EntrySegment {
        let text: String
        let color: NSColor
    }

    private let segmentSeparator = "  │  "

    private func formattedSegments(for entry: PortEntry, duplicate: Bool) -> [EntrySegment] {
        let portText = leftPad("\(entry.port)", to: 5)
        let serviceText = fitColumn(entry.serviceName ?? "-", width: 14)
        let processText = fitColumn("\(entry.command)[\(entry.pid)]", width: 28)
        let commandTail = fitTailColumn(entry.commandLine ?? "-", width: 72)
        let hasService = serviceText.trimmingCharacters(in: .whitespaces) != "-"
        let portColor = duplicate ? NSColor.systemOrange : NSColor.secondaryLabelColor
        let serviceColor = hasService ? NSColor.tertiaryLabelColor : NSColor.quaternaryLabelColor

        return [
            EntrySegment(text: portText, color: portColor),
            EntrySegment(text: serviceText, color: serviceColor),
            EntrySegment(text: processText, color: NSColor.labelColor),
            EntrySegment(text: commandTail, color: NSColor.tertiaryLabelColor)
        ]
    }

    private func fitColumn(_ text: String, width: Int) -> String {
        if text.count == width { return text }
        if text.count < width { return text + String(repeating: " ", count: width - text.count) }

        guard width > 3 else { return String(text.prefix(width)) }
        let kept = width - 3
        return String(text.prefix(kept)) + "..."
    }

    private func leftPad(_ text: String, to width: Int) -> String {
        guard text.count < width else { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    private func fitTailColumn(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard text.count > width else {
            return String(repeating: " ", count: width - text.count) + text
        }

        guard width > 3 else { return String(text.suffix(width)) }
        return "..." + String(text.suffix(width - 3))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        controller = StatusBarController()
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return running.contains { $0.processIdentifier != currentPID }
    }
}

@main
struct ListPPApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
