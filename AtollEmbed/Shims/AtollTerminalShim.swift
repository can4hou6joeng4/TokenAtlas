import Defaults
import SwiftUI

@MainActor
final class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    @Published private(set) var terminalTitle = "Terminal removed"

    private init() {}

    func restartShell() {}
    func refreshTerminalAppearanceIfNeeded() {}
    func focusTerminalIfPossible() {}
    func resignTerminalFirstResponderIfNeeded() {}
}

struct NotchTerminalView: View {
    @Default(.enableTerminalFeature) private var enableTerminalFeature

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text("Terminal is unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if enableTerminalFeature {
                Defaults[.enableTerminalFeature] = false
            }
        }
    }
}
