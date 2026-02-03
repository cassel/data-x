import SwiftUI

struct HeaderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            // Navigation buttons
            navigationButtons

            Divider()
                .frame(height: 24)

            // Breadcrumbs
            breadcrumbsView

            Spacer()

            // Search
            searchField

            Divider()
                .frame(height: 24)

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button {
                appState.scannerViewModel.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(!appState.scannerViewModel.canNavigateBack)
            .help("Back")

            Button {
                appState.scannerViewModel.navigateToRoot()
            } label: {
                Image(systemName: "house")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(appState.scannerViewModel.rootNode == nil)
            .help("Go to root")
        }
    }

    // MARK: - Breadcrumbs

    @ViewBuilder
    private var breadcrumbsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(appState.scannerViewModel.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        appState.scannerViewModel.navigateToBreadcrumb(at: index)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.caption)
                            Text(node.name)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            index == appState.scannerViewModel.breadcrumbs.count - 1
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Search Field

    @ViewBuilder
    private var searchField: some View {
        @Bindable var viewModel = appState.scannerViewModel

        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search files...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .frame(width: 150)
                .onChange(of: viewModel.searchQuery) { _, newValue in
                    appState.scannerViewModel.performSearch(newValue)
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    appState.scannerViewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                appState.showFolderPicker = true
            } label: {
                Image(systemName: "folder")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Open folder")

            Button {
                appState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(appState.scannerViewModel.rootNode == nil || appState.scannerViewModel.isScanning)
            .help("Refresh")

            if let currentNode = appState.scannerViewModel.currentNode {
                Button {
                    FileOperationsService.revealInFinder(currentNode.path)
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
    }
}

#Preview {
    HeaderView()
        .environment(AppState())
        .frame(width: 800)
}
