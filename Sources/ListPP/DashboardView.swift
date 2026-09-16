import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: PortStore

    private var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let scanError = store.scanError {
                        statusCard(
                            title: "Could not scan ports",
                            detail: scanError
                        )
                    } else if store.entries.isEmpty {
                        statusCard(
                            title: "No listening TCP ports",
                            detail: "Nothing is accepting TCP connections right now."
                        )
                    } else if store.visibleEntries.isEmpty {
                        emptyFilterCard
                    } else if store.scope == .all {
                        groupedCards
                    } else {
                        ForEach(store.visibleEntries) { entry in
                            portCard(entry)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 600, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ListPP")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Picker("Sort", selection: $store.sortMode) {
                    ForEach(EntrySortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .labelsHidden()

                Button {
                    store.refresh()
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
            }

            HStack(spacing: 10) {
                TextField("Filter projects, tools, ports…", text: $store.filterText)
                    .textFieldStyle(.roundedBorder)
                Picker("Scope", selection: $store.scope) {
                    ForEach(EntryScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .labelsHidden()
                if !store.filterText.isEmpty {
                    Button("Clear") {
                        store.filterText = ""
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var headerSubtitle: String {
        var parts = [TimeDisplay.updatedText(from: store.lastUpdated)]
        if !store.entries.isEmpty {
            parts.append(store.listeningSummary)
        }
        if !store.duplicatePorts.isEmpty {
            parts.append("\(store.duplicatePorts.count) shared")
        }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var groupedCards: some View {
        if !store.visibleProjectEntries.isEmpty {
            sectionHeader("Project servers", count: store.visibleProjectEntries.count)
            ForEach(store.visibleProjectEntries) { entry in
                portCard(entry)
            }
        }
        if !store.visibleOtherEntries.isEmpty {
            sectionHeader("Other listeners", count: store.visibleOtherEntries.count)
            ForEach(store.visibleOtherEntries) { entry in
                portCard(entry)
            }
        }
    }

    private var emptyFilterCard: some View {
        let title: String
        let detail: String
        if !store.filterText.isEmpty {
            title = "No matches"
            detail = "Nothing matches “\(store.filterText)”."
        } else if store.scope == .project {
            title = "No project servers"
            detail = "Nothing under ~/Project, and no recognized Vite/Next/dev listeners. Switch to All to see system ports."
        } else {
            title = "No matches"
            detail = "Nothing in this view."
        }
        return statusCard(title: title, detail: detail)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title)  ·  \(count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func portCard(_ entry: PortEntry) -> some View {
        PortCardView(
            entry: entry,
            isDuplicate: store.duplicatePorts.contains(entry.port),
            homeDirectory: homeDirectory,
            onRestart: { store.restart(entry) },
            onTerminate: { store.terminate(entry) }
        )
    }

    private func statusCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PortCardView: View {
    let entry: PortEntry
    let isDuplicate: Bool
    let homeDirectory: String
    let onRestart: () -> Void
    let onTerminate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(entry.port)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isDuplicate ? Color.orange : Color.primary)
                    .frame(minWidth: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayTitle)
                        .font(.headline)
                        .textSelection(.enabled)
                    if let location = entry.locationLine(homeDirectory: homeDirectory) {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }
                    Text(entry.identityLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if let badge = entry.displayBadge {
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(entry.isProjectServer ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06), in: Capsule())
                } else if isDuplicate {
                    Text("shared port")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            if isDuplicate {
                Text("Another process is also listening on this port.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !entry.endpoints.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.endpoints.count == 1 ? "Endpoint" : "Endpoints")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.endpoints.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let commandLine = entry.commandLine, !commandLine.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Command")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(commandLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }

            HStack {
                Button("Stop", role: .destructive, action: onTerminate)
                    .help("Send SIGTERM to this process")
                Button("Restart", action: onRestart)
                    .disabled(!entry.canRestart)
                    .help("SIGTERM, then relaunch the same command line in its working directory")
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
