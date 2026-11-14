import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState

    private var strings: Strings { state.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(strings.historyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if state.history.isEmpty {
                Spacer()
                Text(strings.historyEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(state.history) { event in
                    HStack(spacing: 8) {
                        Text(event.appName)
                            .lineLimit(1)
                        Spacer()
                        Text(strings.reasonLabel(event.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Spacer()
                Button(strings.historyClear) {
                    state.clearHistory()
                }
                .disabled(state.history.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
