import { useState } from 'react'
import { Folder, File, Trash2, ExternalLink, ChevronRight } from 'lucide-react'
import { FileNode, formatSize, getFileCategory, categoryColors, directoryColor } from '../types'

interface FileListProps {
  files: FileNode[]
  selectedNode: FileNode | null
  onSelect: (node: FileNode) => void
  onDrillDown: (node: FileNode) => void
  onOpenInFinder: (node: FileNode) => void
  onMoveToTrash: (node: FileNode) => void
}

export function FileList({
  files,
  selectedNode,
  onSelect,
  onDrillDown,
  onOpenInFinder,
  onMoveToTrash,
}: FileListProps) {
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; node: FileNode } | null>(null)

  const handleContextMenu = (e: React.MouseEvent, node: FileNode) => {
    e.preventDefault()
    setContextMenu({ x: e.clientX, y: e.clientY, node })
  }

  const closeContextMenu = () => setContextMenu(null)

  const getNodeColor = (node: FileNode): string => {
    if (node.is_dir) return directoryColor
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }

  return (
    <div className="flex flex-col h-full" onClick={closeContextMenu}>
      {/* Header */}
      <div className="px-4 py-3 border-b border-dark-accent">
        <h2 className="font-medium text-sm text-gray-400 uppercase tracking-wider">Files</h2>
      </div>

      {/* File list */}
      <div className="flex-1 overflow-y-auto">
        {files.length === 0 ? (
          <div className="p-4 text-center text-gray-500">
            No files
          </div>
        ) : (
          <ul className="py-2">
            {files.filter(f => !f.is_hidden).map(file => (
              <li
                key={file.id}
                className={`
                  group flex items-center gap-3 px-4 py-2 cursor-pointer transition-colors
                  ${selectedNode?.id === file.id ? 'bg-dark-accent' : 'hover:bg-dark-accent/50'}
                `}
                onClick={() => onSelect(file)}
                onDoubleClick={() => file.is_dir && onDrillDown(file)}
                onContextMenu={(e) => handleContextMenu(e, file)}
              >
                {/* Color indicator */}
                <div
                  className="w-3 h-3 rounded-sm flex-shrink-0"
                  style={{ backgroundColor: getNodeColor(file) }}
                />

                {/* Icon */}
                {file.is_dir ? (
                  <Folder className="w-4 h-4 text-blue-400 flex-shrink-0" />
                ) : (
                  <File className="w-4 h-4 text-gray-400 flex-shrink-0" />
                )}

                {/* Name and size */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm truncate" title={file.name}>
                    {file.name}
                  </p>
                  <p className="text-xs text-gray-500">
                    {formatSize(file.size)}
                    {file.is_dir && ` - ${file.file_count} files`}
                  </p>
                </div>

                {/* Drill down indicator for directories */}
                {file.is_dir && file.children.length > 0 && (
                  <ChevronRight className="w-4 h-4 text-gray-500 opacity-0 group-hover:opacity-100 transition-opacity" />
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* Context menu */}
      {contextMenu && (
        <div
          className="fixed bg-dark-panel border border-dark-accent rounded-lg shadow-lg py-1 z-50"
          style={{ left: contextMenu.x, top: contextMenu.y }}
        >
          <button
            onClick={() => {
              onOpenInFinder(contextMenu.node)
              closeContextMenu()
            }}
            className="w-full flex items-center gap-2 px-4 py-2 text-sm hover:bg-dark-accent transition-colors"
          >
            <ExternalLink className="w-4 h-4" />
            Show in Finder
          </button>
          <button
            onClick={() => {
              onMoveToTrash(contextMenu.node)
              closeContextMenu()
            }}
            className="w-full flex items-center gap-2 px-4 py-2 text-sm text-red-400 hover:bg-dark-accent transition-colors"
          >
            <Trash2 className="w-4 h-4" />
            Move to Trash
          </button>
        </div>
      )}
    </div>
  )
}
