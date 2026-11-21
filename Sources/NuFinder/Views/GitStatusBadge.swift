import SwiftUI

struct GitStatusBadge: View {
    let url: URL

    @ObservedObject private var git = GitStatusService.shared
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false

    var body: some View {
        if gitStatusEnabled, let state = git.state(for: url) {
            Text(state.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: state))
                .help(description(for: state))
                .accessibilityLabel(description(for: state))
        }
    }

    private func color(for state: GitFileState) -> Color {
        switch state {
        case .added, .untracked: .green
        case .modified, .renamed: .orange
        case .deleted, .conflicted: .red
        case .ignored: .secondary
        }
    }

    private func description(for state: GitFileState) -> String {
        switch state {
        case .modified: String(localized: "Git: Modified")
        case .added: String(localized: "Git: Added")
        case .deleted: String(localized: "Git: Deleted")
        case .renamed: String(localized: "Git: Renamed")
        case .conflicted: String(localized: "Git: Conflict")
        case .untracked: String(localized: "Git: Untracked")
        case .ignored: String(localized: "Git: Ignored")
        }
    }
}
