import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: PortStore

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
                        statusCard(
                            title: "No matches",
                            detail: "Nothing matches “\(store.filterText)”."
                        )
                    } else {
                        ForEach(store.visibleEntries) { entry in
                            PortCardView(
                                entry: entry,
                                isDuplicate: store.duplicatePorts.contains(entry.port),
                                onRestart: { store.restart(entry) },
                                onTerminate: { store.terminate(entry) }
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 560, minHeight: 480)
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
                TextField("Filter ports, processes, users…", text: $store.filterText)
                    .textFieldStyle(.roundedBorder)
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
                    Text(entry.command)
                        .font(.headline)
                    Text("PID \(entry.pid)  ·  \(entry.user)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if let service = entry.serviceName {
                    Text(service)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                } else if isDuplicate {
                    Text("shared port")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            if isDuplicate, entry.serviceName != nil {
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
                Spacer()
                Button("Restart", action: onRestart)
                    .disabled(!entry.canRestart)
                    .help("SIGTERM, then relaunch the same command line")
                Button("Stop", role: .destructive, action: onTerminate)
                    .help("Send SIGTERM to this process")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
