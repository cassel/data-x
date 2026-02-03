import SwiftUI
import Charts

struct BarChartView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var selectedChild: FileNode?

    private var topChildren: [FileNode] {
        (node.sortedChildren ?? []).prefix(20).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            if topChildren.isEmpty {
                emptyView
            } else {
                chartView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No data to display")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var chartView: some View {
        Chart(topChildren, id: \.id) { child in
            BarMark(
                x: .value("Size", child.size),
                y: .value("Name", child.name)
            )
            .foregroundStyle(child.isDirectory ? FileCategory.folders.color : child.category.color)
            .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                Text(child.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        HStack(spacing: 4) {
                            let child = topChildren.first { $0.name == name }
                            Image(systemName: child?.isDirectory == true ? "folder.fill" : (child?.category.icon ?? "doc.fill"))
                                .font(.caption2)
                                .foregroundColor(child?.isDirectory == true ? FileCategory.folders.color : child?.category.color)
                            Text(name)
                                .lineLimit(1)
                                .frame(maxWidth: 150, alignment: .leading)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let bytes = value.as(UInt64.self) {
                        Text(SizeFormatter.format(bytes))
                    }
                }
                AxisGridLine()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let name: String = proxy.value(atY: value.location.y) {
                                    if let child = topChildren.first(where: { $0.name == name }) {
                                        if child.isDirectory {
                                            onSelect(child)
                                        }
                                    }
                                }
                            }
                    )
            }
        }
        .padding()

        // Legend
        legendView
    }

    @ViewBuilder
    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(FileCategory.allCases, id: \.self) { category in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 8, height: 8)
                        Text(category.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    let root = FileNode(url: URL(fileURLWithPath: "/test"), isDirectory: true)
    let child1 = FileNode(url: URL(fileURLWithPath: "/test/large.zip"), isDirectory: false)
    child1.size = 1024 * 1024 * 500
    let child2 = FileNode(url: URL(fileURLWithPath: "/test/medium"), isDirectory: true)
    child2.size = 1024 * 1024 * 200
    let child3 = FileNode(url: URL(fileURLWithPath: "/test/small.txt"), isDirectory: false)
    child3.size = 1024 * 50
    root.children = [child1, child2, child3]

    return BarChartView(node: root) { _ in }
        .frame(width: 600, height: 400)
}
