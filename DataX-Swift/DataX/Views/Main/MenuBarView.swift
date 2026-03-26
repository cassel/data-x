import SwiftUI

enum DiskUsageSeverity: Equatable {
    case normal
    case warning
    case critical

    static func resolve(for percentage: Double) -> Self {
        if percentage > 90 {
            .critical
        } else if percentage > 75 {
            .warning
        } else {
            .normal
        }
    }

    var color: Color {
        switch self {
        case .normal:
            .accentColor
        case .warning:
            .orange
        case .critical:
            .red
        }
    }

    var summaryLabel: String {
        switch self {
        case .normal:
            "Normal"
        case .warning:
            "Warning"
        case .critical:
            "Critical"
        }
    }
}

enum MenuBarDiskSource: Equatable {
    case liveScan
    case fallbackLocalVolume

    var subtitle: String {
        switch self {
        case .liveScan:
            "Current local scan"
        case .fallbackLocalVolume:
            "Local volume fallback"
        }
    }
}

enum MenuBarDiskInfoState {
    case available(DiskInfo, source: MenuBarDiskSource)
    case unavailable(fallbackURL: URL)

    var accessibilityValue: String {
        switch self {
        case .available(let diskInfo, let source):
            let usedPercentage = Int(diskInfo.usedPercentage.rounded())
            return [
                diskInfo.volumeName,
                "\(usedPercentage) percent used",
                "\(diskInfo.formattedFree) free of \(diskInfo.formattedTotal)",
                source.subtitle
            ]
            .joined(separator: ", ")
        case .unavailable:
            return "Disk usage unavailable"
        }
    }
}

enum MenuBarDiskResolver {
    static func fallbackURL(
        lastScannedURL: URL?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        (lastScannedURL ?? homeDirectory).standardizedFileURL
    }

    static func preferredDiskInfo(
        live: DiskInfo?,
        lastScannedURL: URL?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        diskInfoProvider: (URL) throws -> DiskInfo = DiskInfo.forPath
    ) -> MenuBarDiskInfoState {
        if let live {
            return .available(live, source: .liveScan)
        }

        let fallbackURL = fallbackURL(lastScannedURL: lastScannedURL, homeDirectory: homeDirectory)

        do {
            return .available(try diskInfoProvider(fallbackURL), source: .fallbackLocalVolume)
        } catch {
            return .unavailable(fallbackURL: fallbackURL)
        }
    }
}

enum MenuBarScanNowIntent: Equatable {
    case rescan(URL)
    case openFolderPicker

    static func resolve(lastScannedURL: URL?) -> Self {
        guard let lastScannedURL else {
            return .openFolderPicker
        }

        return .rescan(lastScannedURL.standardizedFileURL)
    }
}

struct DiskUsageBar: View {
    let percentage: Double
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let normalized = min(max(percentage / 100, 0), 1)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(DiskUsageSeverity.resolve(for: percentage).color)
                    .frame(width: geometry.size.width * normalized, height: height)
            }
        }
        .frame(height: height)
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarDiskStateObserver { diskState in
            VStack(alignment: .leading, spacing: 16) {
                switch diskState {
                case .available(let diskInfo, let source):
                    availableContent(diskInfo: diskInfo, source: source)
                case .unavailable:
                    unavailableContent
                }

                Button("Scan Now") {
                    appState.scanNowFromMenuBar(openWindow: openWindow)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    @ViewBuilder
    private func availableContent(diskInfo: DiskInfo, source: MenuBarDiskSource) -> some View {
        let severity = DiskUsageSeverity.resolve(for: diskInfo.usedPercentage)
        let usageText = "\(Int(diskInfo.usedPercentage.rounded()))% used"

        HStack(alignment: .center, spacing: 12) {
            DiskUsageGaugeView(
                percentage: diskInfo.usedPercentage,
                size: 34,
                lineWidth: 3,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(diskInfo.volumeName)
                    .font(.headline)
                    .lineLimit(1)

                Text(source.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Disk usage"))
        .accessibilityValue(Text(MenuBarDiskInfoState.available(diskInfo, source: source).accessibilityValue))

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                metricValue(title: "Used", value: diskInfo.formattedUsed)
                Spacer()
                metricValue(title: "Free", value: diskInfo.formattedFree)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(usageText)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(severity.summaryLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(severity.color)
                }

                DiskUsageBar(
                    percentage: diskInfo.usedPercentage,
                    height: 8,
                    cornerRadius: 4
                )
                .frame(height: 8)
                .accessibilityLabel(Text("Disk usage bar"))
                .accessibilityValue(Text("\(usageText), \(severity.summaryLabel.lowercased())"))
            }

            Text("Volume total: \(diskInfo.formattedTotal)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                DiskUsageGaugeView(
                    percentage: nil,
                    size: 34,
                    lineWidth: 3,
                    iconSize: 14
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Disk usage unavailable")
                        .font(.headline)

                    Text("Open the main window to grant access to a local folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Disk usage unavailable"))
            .accessibilityValue(Text("Open the main window to grant access to a local folder"))
        }
    }

    private func metricValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct MenuBarExtraLabelView: View {
    var body: some View {
        MenuBarDiskStateObserver { diskState in
            DiskUsageGaugeView(
                percentage: percentage(for: diskState),
                size: 18,
                lineWidth: 2,
                iconSize: 8
            )
            .frame(width: 18, height: 18)
            .padding(.vertical, 2)
            .accessibilityLabel(Text("Disk usage gauge"))
            .accessibilityValue(Text(diskState.accessibilityValue))
        }
    }

    private func percentage(for diskState: MenuBarDiskInfoState) -> Double? {
        switch diskState {
        case .available(let diskInfo, _):
            diskInfo.usedPercentage
        case .unavailable:
            nil
        }
    }
}

private struct MenuBarDiskRefreshToken: Equatable {
    let liveVolumePath: String?
    let totalSpace: UInt64?
    let usedSpace: UInt64?
    let freeSpace: UInt64?
    let lastScannedPath: String?
}

private struct MenuBarDiskStateObserver<Content: View>: View {
    @Environment(AppState.self) private var appState
    @State private var diskState: MenuBarDiskInfoState = .unavailable(
        fallbackURL: FileManager.default.homeDirectoryForCurrentUser
    )

    private let content: (MenuBarDiskInfoState) -> Content

    init(@ViewBuilder content: @escaping (MenuBarDiskInfoState) -> Content) {
        self.content = content
    }

    var body: some View {
        content(diskState)
            .task(id: refreshToken) {
                diskState = MenuBarDiskResolver.preferredDiskInfo(
                    live: appState.scannerViewModel.diskInfo,
                    lastScannedURL: appState.lastScannedURL
                )
            }
    }

    private var refreshToken: MenuBarDiskRefreshToken {
        let live = appState.scannerViewModel.diskInfo

        return MenuBarDiskRefreshToken(
            liveVolumePath: live?.volumePath.standardizedFileURL.path,
            totalSpace: live?.totalSpace,
            usedSpace: live?.usedSpace,
            freeSpace: live?.freeSpace,
            lastScannedPath: appState.lastScannedURL?.standardizedFileURL.path
        )
    }
}

private struct DiskUsageGaugeView: View {
    let percentage: Double?
    let size: CGFloat
    let lineWidth: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)

            if let percentage {
                Circle()
                    .trim(from: 0, to: min(max(percentage / 100, 0), 1))
                    .stroke(
                        DiskUsageSeverity.resolve(for: percentage).color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(
                        Color.secondary,
                        style: StrokeStyle(lineWidth: lineWidth, dash: [2, 2])
                    )
            }

            Image(systemName: percentage == nil ? "internaldrive" : "internaldrive.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(percentage == nil ? .secondary : .primary)
        }
        .frame(width: size, height: size)
    }
}
