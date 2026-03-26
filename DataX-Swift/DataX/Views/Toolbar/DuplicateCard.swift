import SwiftUI

struct DuplicateCard: View {
    let group: DuplicateGroup
    let onSelectPath: (String) -> Void
    let onMoveToTrash: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.titleText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(group.reclaimableText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(SizeFormatter.format(group.size))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ForEach(group.files) { file in
                duplicateRow(for: file)
            }
        }
        .padding(.vertical, 6)
    }

    private func duplicateRow(for file: DuplicateFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onSelectPath(file.path)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(file.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Text(file.modificationLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(file.path)

            if group.isSuggestedOriginal(file) {
                Text("Keep Suggested")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            } else {
                Button(role: .destructive) {
                    onMoveToTrash(file.path)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Move to Trash")
            }
        }
        .padding(.leading, 8)
    }
}
