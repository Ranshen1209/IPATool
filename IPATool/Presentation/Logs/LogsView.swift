import SwiftUI

struct LogsView: View {
    @Bindable var model: AppModel
    @State private var searchText = ""
    @State private var selectedLevels = Set(LogLevel.allCases)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs")
                        .font(.title2.weight(.semibold))
                    Text("Review task, protocol, and archive rewrite activity. Filter the stream before exporting or debugging.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Level") {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Toggle(level.rawValue.capitalized, isOn: Binding(
                            get: { selectedLevels.contains(level) },
                            set: { isEnabled in
                                if isEnabled {
                                    selectedLevels.insert(level)
                                } else if selectedLevels.count > 1 {
                                    selectedLevels.remove(level)
                                }
                            }
                        ))
                    }
                }
                Button("Copy Visible") {
                    model.copyToPasteboard(renderedLogText)
                }
                Button("Clear") {
                    Task {
                        await model.clearLogs()
                    }
                }
                Button("Reload") {
                    Task {
                        await model.refreshLogs()
                    }
                }
            }

            TextField("Search messages or categories", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(filteredLogs) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.level.rawValue.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: entry.level))
                        Text(entry.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .padding(20)
        .navigationTitle("Logs")
    }

    private var filteredLogs: [LogEntry] {
        model.logs.filter { entry in
            let levelMatches = selectedLevels.contains(entry.level)
            let searchMatches = searchText.isEmpty
                || entry.category.localizedCaseInsensitiveContains(searchText)
                || entry.message.localizedCaseInsensitiveContains(searchText)
            return levelMatches && searchMatches
        }
    }

    private var renderedLogText: String {
        filteredLogs.map { entry in
            "\(entry.date.formatted(date: .numeric, time: .standard)) [\(entry.level.rawValue.uppercased())] \(entry.category): \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:
            .secondary
        case .info:
            .blue
        case .notice:
            .orange
        case .error:
            .red
        }
    }
}
