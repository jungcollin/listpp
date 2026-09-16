import AppKit
import Foundation

final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var duplicatePorts = Set<Int>()
    @Published var sortMode: EntrySortMode = .newest {
        didSet {
            guard oldValue != sortMode else { return }
            refresh()
        }
    }
    @Published var filterText = ""
    @Published var scope: EntryScope = .project
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var scanError: String?

    var openDashboard: () -> Void = {}

    var projectEntries: [PortEntry] {
        entries.filter(\.isProjectServer)
    }

    var otherEntries: [PortEntry] {
        entries.filter { !$0.isProjectServer }
    }

    var scopedEntries: [PortEntry] {
        switch scope {
        case .project:
            return projectEntries
        case .all:
            return entries
        case .other:
            return otherEntries
        }
    }

    var visibleEntries: [PortEntry] {
        filter(scopedEntries)
    }

    var visibleProjectEntries: [PortEntry] {
        visibleEntries.filter(\.isProjectServer)
    }

    var visibleOtherEntries: [PortEntry] {
        visibleEntries.filter { !$0.isProjectServer }
    }

    var previewEntries: [PortEntry] {
        if !projectEntries.isEmpty {
            return projectEntries
        }
        return entries
    }

    var listeningSummary: String {
        let total = entries.count
        let projects = projectEntries.count
        if total == 0 {
            return "No listening ports"
        }
        if projects == 0 {
            return total == 1 ? "1 listening port" : "\(total) listening ports"
        }
        let projectPart = projects == 1 ? "1 project server" : "\(projects) project servers"
        if projects == total {
            return projectPart
        }
        return "\(projectPart)  ·  \(total) listening"
    }

    private let scanner = PortScanner()
    private var refreshTimer: Timer?
    private var scanGeneration = 0

    func start() {
        refresh()

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh(showProgress: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(showProgress: Bool = true) {
        scanGeneration += 1
        let generation = scanGeneration
        let mode = sortMode
        if showProgress {
            isRefreshing = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let outcome = self.scanner.scanListeningTCPPorts(sortedBy: mode)
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                switch outcome {
                case .success(let entries):
                    self.entries = entries
                    self.duplicatePorts = Self.findDuplicatePorts(in: entries)
                    self.scanError = nil
                case .failure(let message):
                    self.entries = []
                    self.duplicatePorts = []
                    self.scanError = message
                }
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }

    func showDashboard() {
        openDashboard()
    }

    func terminate(_ entry: PortEntry) {
        do {
            try ProcessActions.terminate(pid: entry.pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refresh()
            }
        } catch {
            AppAlerts.showError(title: "Terminate Failed", detail: error.localizedDescription)
        }
    }

    func restart(_ entry: PortEntry) {
        guard let commandLine = entry.commandLine, !commandLine.isEmpty else {
            AppAlerts.showError(title: "Restart Failed", detail: ProcessActionError.missingCommandLine.localizedDescription)
            return
        }
        guard AppAlerts.confirmRestart(entry: entry) else { return }

        do {
            try ProcessActions.terminate(pid: entry.pid)
            try ProcessActions.relaunch(commandLine: commandLine, workingDirectory: entry.workingDirectory)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.refresh()
            }
        } catch {
            AppAlerts.showError(title: "Restart Failed", detail: error.localizedDescription)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private static func findDuplicatePorts(in entries: [PortEntry]) -> Set<Int> {
        var frequency: [Int: Int] = [:]
        for entry in entries {
            frequency[entry.port, default: 0] += 1
        }
        return Set(frequency.compactMap { port, count in
            count > 1 ? port : nil
        })
    }

    private func filter(_ entries: [PortEntry]) -> [PortEntry] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.searchText.contains(query) }
    }
}
