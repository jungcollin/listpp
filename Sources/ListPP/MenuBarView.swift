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
        .frame(width: 360)
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
            if store.projectEntries.isEmpty, !store.entries.isEmpty {
                Text("No leftover project servers — Open to inspect system listeners")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !store.duplicatePorts.isEmpty {
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
            let preview = Array(store.previewEntries.prefix(previewLimit))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(preview) { entry in
                        compactRow(entry)
                    }
                    if store.previewEntries.count > previewLimit {
                        Text("Open dashboard for \(store.previewEntries.count - previewLimit) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if store.previewEntries.count < store.entries.count {
                        Text("Open dashboard for \(store.entries.count - store.previewEntries.count) other listeners")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func compactRow(_ entry: PortEntry) -> some View {
        let duplicate = store.duplicatePorts.contains(entry.port)
        return HStack(alignment: .center, spacing: 8) {
            Text("\(entry.port)")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(duplicate ? Color.orange : Color.primary)
                .frame(width: 48, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(compactIdentity(entry))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Stop", role: .destructive) {
                store.terminate(entry)
            }
            .controlSize(.mini)
            .help("Send SIGTERM to this process")
        }
        .padding(.vertical, 2)
    }

    private func compactIdentity(_ entry: PortEntry) -> String {
        var parts: [String] = []
        if let tool = entry.toolLabel, tool.caseInsensitiveCompare(entry.displayTitle) != .orderedSame {
            parts.append(tool)
        }
        if entry.command.caseInsensitiveCompare(entry.displayTitle) != .orderedSame,
           entry.command.caseInsensitiveCompare(entry.toolLabel ?? "") != .orderedSame {
            parts.append(entry.command)
        }
        if parts.isEmpty {
            parts.append("PID \(entry.pid)")
        }
        return parts.joined(separator: " · ")
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
