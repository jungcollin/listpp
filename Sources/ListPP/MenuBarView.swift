import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: PortStore

    private let previewLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("ListPP")
                .font(.headline)
            Spacer()
            Text(TimeDisplay.timeText(from: store.lastUpdated))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.listeningSummary)
                .font(.caption.weight(.semibold))
            if !store.duplicatePorts.isEmpty {
                Text("\(store.duplicatePorts.count) ports shared by more than one process")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let scanError = store.scanError {
            Text(scanError)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.entries.isEmpty {
            Text("No listening TCP ports.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let preview = Array(store.entries.prefix(previewLimit))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(preview) { entry in
                        compactRow(entry)
                    }
                    if store.entries.count > previewLimit {
                        Text("Open dashboard for \(store.entries.count - previewLimit) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func compactRow(_ entry: PortEntry) -> some View {
        let duplicate = store.duplicatePorts.contains(entry.port)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(entry.port)")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(duplicate ? Color.orange : Color.primary)
                    .frame(width: 48, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.command)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let service = entry.serviceName {
                            Text(service)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text("PID \(entry.pid)  ·  \(entry.user)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Restart") {
                    store.restart(entry)
                }
                .disabled(!entry.canRestart)
                .help("SIGTERM, then relaunch the same command line")
                Button("Stop", role: .destructive) {
                    store.terminate(entry)
                }
                .help("Send SIGTERM to this process")
            }
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                store.refresh()
            }
            .disabled(store.isRefreshing)
            Spacer()
            Button("Open") {
                store.showDashboard()
            }
            Button("Quit") {
                store.quit()
            }
        }
        .controlSize(.small)
    }
}
