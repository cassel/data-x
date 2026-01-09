import { useState, useCallback } from 'react'
import { ChevronRight, ChevronDown, Folder, FolderOpen, File, Trash2, ExternalLink } from 'lucide-react'
import { FileNode, formatSize, getFileCategory, categoryColors, directoryColor } from '../types'

interface FileTreeProps {
  root: FileNode
  selectedNode: FileNode | null
  onSelect: (node: FileNode) => void
  onDrillDown: (node: FileNode) => void
  onOpenInFinder: (node: FileNode) => void
  onMoveToTrash: (node: FileNode) => void
}

interface TreeNodeProps {
  node: FileNode
  depth: number
  selectedNode: FileNode | null
  expandedIds: Set<string>
  onToggle: (id: string) => void
  onSelect: (node: FileNode) => void
  onDrillDown: (node: FileNode) => void
  onContextMenu: (e: React.MouseEvent, node: FileNode) => void
}

function TreeNode({
  node,
  depth,
  selectedNode,
  expandedIds,
  onToggle,
  onSelect,
  onDrillDown,
  onContextMenu,
}: TreeNodeProps) {
  const isExpanded = expandedIds.has(node.id.toString())
  const isSelected = selectedNode?.id === node.id
  const hasChildren = node.is_dir && node.children.length > 0

  const getNodeColor = (n: FileNode): string => {
    if (n.is_dir) return directoryColor
    const category = getFileCategory(n.extension)
    return categoryColors[category]
  }

  const handleClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    onSelect(node)
  }

  const handleDoubleClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (node.is_dir) {
      onDrillDown(node)
    }
  }

  const handleToggle = (e: React.MouseEvent) => {
    e.stopPropagation()
    onToggle(node.id.toString())
  }

  if (node.is_hidden) return null

  return (
    <div>
      <div
        className={`
          flex items-center gap-1 px-2 py-1 cursor-pointer transition-colors
          ${isSelected ? 'bg-accent/30' : 'hover:bg-dark-accent/50'}
        `}
        style={{ paddingLeft: `${depth * 16 + 8}px` }}
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        onContextMenu={(e) => onContextMenu(e, node)}
      >
        {/* Expand/collapse toggle */}
        {hasChildren ? (
          <button
            onClick={handleToggle}
            className="p-0.5 hover:bg-dark-accent rounded"
          >
            {isExpanded ? (
              <ChevronDown className="w-3.5 h-3.5 text-gray-400" />
            ) : (
              <ChevronRight className="w-3.5 h-3.5 text-gray-400" />
            )}
          </button>
        ) : (
          <span className="w-4.5" />
        )}

        {/* Color indicator */}
        <div
          className="w-2.5 h-2.5 rounded-sm flex-shrink-0"
          style={{ backgroundColor: getNodeColor(node) }}
        />

        {/* Icon */}
        {node.is_dir ? (
          isExpanded ? (
            <FolderOpen className="w-4 h-4 text-blue-400 flex-shrink-0" />
          ) : (
            <Folder className="w-4 h-4 text-blue-400 flex-shrink-0" />
          )
        ) : (
          <File className="w-4 h-4 text-gray-400 flex-shrink-0" />
        )}

        {/* Name */}
        <span className="text-sm truncate flex-1" title={node.name}>
          {node.name}
        </span>

        {/* Size */}
        <span className="text-xs text-gray-500 flex-shrink-0">
          {formatSize(node.size)}
        </span>
      </div>

      {/* Children */}
      {hasChildren && isExpanded && (
        <div>
          {node.children
            .filter(child => !child.is_hidden)
            .map(child => (
              <TreeNode
                key={child.id}
                node={child}
                depth={depth + 1}
                selectedNode={selectedNode}
                expandedIds={expandedIds}
                onToggle={onToggle}
                onSelect={onSelect}
                onDrillDown={onDrillDown}
                onContextMenu={onContextMenu}
              />
            ))}
        </div>
      )}
    </div>
  )
}

export function FileTree({
  root,
  selectedNode,
  onSelect,
  onDrillDown,
  onOpenInFinder,
  onMoveToTrash,
}: FileTreeProps) {
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set([root.id.toString()]))
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; node: FileNode } | null>(null)

  const handleToggle = useCallback((id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }, [])

  const handleContextMenu = useCallback((e: React.MouseEvent, node: FileNode) => {
    e.preventDefault()
    setContextMenu({ x: e.clientX, y: e.clientY, node })
  }, [])

  const closeContextMenu = () => setContextMenu(null)

  return (
    <div className="flex flex-col h-full" onClick={closeContextMenu}>
      {/* Header */}
      <div className="px-4 py-3 border-b border-dark-accent">
        <h2 className="font-medium text-sm text-gray-400 uppercase tracking-wider">Files</h2>
      </div>

      {/* Tree */}
      <div className="flex-1 overflow-y-auto py-1">
        {root.children.filter(c => !c.is_hidden).length === 0 ? (
          <div className="p-4 text-center text-gray-500 text-sm">
            No files
          </div>
        ) : (
          root.children
            .filter(child => !child.is_hidden)
            .map(child => (
              <TreeNode
                key={child.id}
                node={child}
                depth={0}
                selectedNode={selectedNode}
                expandedIds={expandedIds}
                onToggle={handleToggle}
                onSelect={onSelect}
                onDrillDown={onDrillDown}
                onContextMenu={handleContextMenu}
              />
            ))
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
