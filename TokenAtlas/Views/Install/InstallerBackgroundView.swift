import AppKit
import SwiftUI

/// A previewable mock of the DMG install window. The release DMG uses Finder's
/// real app and Applications icons over a matching generated background.
struct InstallerBackgroundView: View {
    private enum Layout {
        static let size = CGSize(width: 1360, height: 840)
        static let appPosition = CGPoint(x: 410, y: 490)
        static let applicationsPosition = CGPoint(x: 950, y: 490)
        static let iconSize: CGFloat = 128
        static let landingPadSize = CGSize(width: 220, height: 196)
    }

    var showsMockIcons = true

    var body: some View {
        ZStack {
            Color(red: 0.953, green: 0.973, blue: 0.968)

            Rectangle()
                .fill(Color(red: 0.106, green: 0.129, blue: 0.157))
                .frame(height: 18)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 18) {
                Text(verbatim: "Drag TokenAtlas to Applications")
                    .font(.system(size: 62, weight: .medium))
                    .foregroundStyle(Color(red: 0.105, green: 0.118, blue: 0.135))
                Text(verbatim: "Install once. Future releases arrive through Sparkle updates.")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color(red: 0.330, green: 0.380, blue: 0.420))
            }
            .position(x: Layout.size.width / 2, y: 204)

            InstallerLandingPad()
                .frame(width: Layout.landingPadSize.width, height: Layout.landingPadSize.height)
                .position(Layout.appPosition)

            InstallerLandingPad()
                .frame(width: Layout.landingPadSize.width, height: Layout.landingPadSize.height)
                .position(Layout.applicationsPosition)

            InstallerArrow()
                .stroke(
                    Color(red: 0.913, green: 0.365, blue: 0.208),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 172, height: 48)
                .position(x: 680, y: 490)

            if showsMockIcons {
                InstallerIconPair(
                    appPosition: Layout.appPosition,
                    applicationsPosition: Layout.applicationsPosition,
                    iconSize: Layout.iconSize
                )
            }

            Text(verbatim: "Open the disk image, then drag the app icon onto the Applications folder.")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(red: 0.370, green: 0.430, blue: 0.460))
                .position(x: Layout.size.width / 2, y: 708)
        }
        .frame(width: Layout.size.width, height: Layout.size.height)
    }
}

private struct InstallerLandingPad: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.white.opacity(0.82))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color(red: 0.760, green: 0.825, blue: 0.840).opacity(0.70), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 10)
    }
}

private struct InstallerIconPair: View {
    var appPosition: CGPoint
    var applicationsPosition: CGPoint
    var iconSize: CGFloat

    var body: some View {
        ZStack {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                .position(appPosition)

            Text(verbatim: "TokenAtlas")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Color(red: 0.02, green: 0.37, blue: 0.88), in: Capsule())
                .position(x: appPosition.x, y: appPosition.y + 96)

            ApplicationsFolderIcon(iconSize: iconSize)
                .position(applicationsPosition)

            Text(verbatim: "Applications")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.15))
                .position(x: applicationsPosition.x, y: applicationsPosition.y + 96)
        }
    }

    @MainActor
    private var appIcon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApplication.shared.applicationIconImage
    }
}

private struct ApplicationsFolderIcon: View {
    var iconSize: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: applicationsIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize + 26, height: iconSize + 26)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 7)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.95),
                            Color(red: 0.82, green: 0.83, blue: 0.83),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 1))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 31, weight: .heavy))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.19))
                        .offset(x: 2, y: -1)
                }
                .offset(x: -12, y: 7)
        }
        .frame(width: iconSize + 52, height: iconSize + 52)
    }

    @MainActor
    private var applicationsIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: "/Applications")
        icon.size = NSSize(width: iconSize + 26, height: iconSize + 26)
        return icon
    }
}

private struct InstallerArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - 32, y: rect.midY - 24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 32, y: rect.midY + 24))
        return path
    }
}

#if DEBUG
private struct InstallerWindowPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            FinderTitleBar()
            InstallerBackgroundView()
            FinderPathBar()
        }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 18)
        .padding(24)
    }
}

private struct FinderTitleBar: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 14) {
                trafficLight(.red)
                trafficLight(.yellow)
                trafficLight(.green)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: "TokenAtlas")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.73, green: 0.69, blue: 0.70))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(red: 0.16, green: 0.11, blue: 0.13))
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
    }
}

private struct FinderPathBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.app.fill")
            Text(verbatim: "TokenAtlas")
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(verbatim: "TokenAtlas")
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color(red: 0.72, green: 0.68, blue: 0.69))
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(Color(red: 0.20, green: 0.15, blue: 0.17))
    }
}

#Preview("DMG install window") {
    InstallerWindowPreview()
        .preferredColorScheme(.light)
}

#Preview("DMG background only") {
    InstallerBackgroundView()
        .preferredColorScheme(.light)
}
#endif
