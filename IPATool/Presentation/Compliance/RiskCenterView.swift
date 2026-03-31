import SwiftUI

struct RiskCenterView: View {
    let risks: [OperationalRisk]
    @State private var selectedLevel: OperationalRiskLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Menu(selectedLevel?.rawValue ?? "All Levels") {
                    Button("All Levels") {
                        selectedLevel = nil
                    }
                    Divider()
                    ForEach(OperationalRiskLevel.allCases, id: \.self) { level in
                        Button(level.rawValue) {
                            selectedLevel = level
                        }
                    }
                }
                Button("Copy Visible") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(renderedRiskText, forType: .string)
                }
            }

            List {
                ForEach(visibleLevels, id: \.self) { level in
                    Section(level.rawValue) {
                        ForEach(risks.filter { $0.level == level }) { risk in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(risk.title)
                                    .font(.headline)
                                Text(risk.summary)
                                    .foregroundStyle(.primary)
                                Text("Impact: \(risk.impact)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Recommendation: \(risk.recommendation)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("Operational Risks")
    }

    private var visibleLevels: [OperationalRiskLevel] {
        if let selectedLevel {
            return [selectedLevel]
        }
        return OperationalRiskLevel.allCases
    }

    private var renderedRiskText: String {
        visibleLevels.flatMap { level in
            risks.filter { $0.level == level }.map { risk in
                """
                [\(risk.level.rawValue)] \(risk.title)
                Summary: \(risk.summary)
                Impact: \(risk.impact)
                Recommendation: \(risk.recommendation)
                """
            }
        }
        .joined(separator: "\n\n")
    }
}
