import { useState, useMemo } from 'react'
import {
  X,
  Trash2,
  ChevronDown,
  ChevronRight,
  Check,
  File,
  AlertTriangle,
  CheckCircle,
  Loader2,
} from 'lucide-react'
import { invoke } from '@tauri-apps/api/core'
import {
  DuplicateScanResult,
  DuplicateGroup,
  DeleteResult,
  formatSize,
} from '../types'

interface DuplicateResultsProps {
  isOpen: boolean
  onClose: () => void
  result: DuplicateScanResult
  onRefresh: () => void
}

export function DuplicateResults({
  isOpen,
  onClose,
  result,
  onRefresh,
}: DuplicateResultsProps) {
  const [selectedPaths, setSelectedPaths] = useState<Set<string>>(new Set())
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set())
  const [isDeleting, setIsDeleting] = useState(false)
  const [deleteResult, setDeleteResult] = useState<DeleteResult | null>(null)
  const [toTrash, setToTrash] = useState(true)

  // Calculate selected stats
  const selectedStats = useMemo(() => {
    let count = 0
    let size = 0

    for (const group of result.groups) {
      for (const file of group.files) {
        if (selectedPaths.has(file.path)) {
          count++
          size += file.size
        }
      }
    }

    return { count, size }
  }, [result.groups, selectedPaths])

  const toggleGroup = (hash: string) => {
    setExpandedGroups((prev) => {
      const next = new Set(prev)
      if (next.has(hash)) {
        next.delete(hash)
      } else {
        next.add(hash)
      }
      return next
    })
  }

  const toggleFile = (path: string) => {
    setSelectedPaths((prev) => {
      const next = new Set(prev)
      if (next.has(path)) {
        next.delete(path)
      } else {
        next.add(path)
      }
      return next
    })
  }

  const selectAllDuplicates = () => {
    const paths = new Set<string>()
    for (const group of result.groups) {
      // Skip the first file (suggested original), select the rest
      for (let i = 1; i < group.files.length; i++) {
        paths.add(group.files[i].path)
      }
    }
    setSelectedPaths(paths)
  }

  const clearSelection = () => {
    setSelectedPaths(new Set())
  }

  const handleDelete = async () => {
    if (selectedPaths.size === 0) return

    setIsDeleting(true)
    setDeleteResult(null)

    try {
      const paths = Array.from(selectedPaths)
      const result = await invoke<DeleteResult>('delete_files', {
        paths,
        toTrash,
      })

      setDeleteResult(result)

      // Remove successfully deleted files from selection
      if (result.deleted > 0) {
        setSelectedPaths(new Set(result.failed.map((f) => f.split(':')[0])))
      }
    } catch (e) {
      setDeleteResult({
        deleted: 0,
        bytes_freed: 0,
        failed: [String(e)],
      })
    } finally {
      setIsDeleting(false)
    }
  }

  const handleCloseAndRefresh = () => {
    if (deleteResult && deleteResult.deleted > 0) {
      onRefresh()
    }
    onClose()
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-dark-panel border border-dark-accent rounded-lg w-full max-w-3xl max-h-[80vh] flex flex-col shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-dark-accent flex-shrink-0">
          <div>
            <h2 className="font-semibold">Duplicate Files Found</h2>
            <p className="text-sm text-gray-400">
              {result.total_duplicates} duplicates wasting {formatSize(result.wasted_space)}
            </p>
          </div>
          <button
            onClick={handleCloseAndRefresh}
            className="p-1 rounded hover:bg-dark-accent transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Delete result banner */}
        {deleteResult && (
          <div
            className={`px-4 py-3 flex items-start gap-2 border-b border-dark-accent flex-shrink-0 ${
              deleteResult.failed.length > 0
                ? 'bg-yellow-500/10'
                : 'bg-green-500/10'
            }`}
          >
            {deleteResult.failed.length > 0 ? (
              <AlertTriangle className="w-5 h-5 text-yellow-400 flex-shrink-0 mt-0.5" />
            ) : (
              <CheckCircle className="w-5 h-5 text-green-400 flex-shrink-0 mt-0.5" />
            )}
            <div className="flex-1">
              <p className="text-sm">
                Deleted {deleteResult.deleted} files, freed {formatSize(deleteResult.bytes_freed)}
              </p>
              {deleteResult.failed.length > 0 && (
                <div className="mt-1 text-xs text-yellow-300">
                  {deleteResult.failed.length} files failed to delete
                </div>
              )}
            </div>
            <button
              onClick={() => setDeleteResult(null)}
              className="p-1 rounded hover:bg-dark-accent"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Selection controls */}
        <div className="flex items-center justify-between px-4 py-2 bg-dark-bg/50 border-b border-dark-accent flex-shrink-0">
          <div className="flex items-center gap-4">
            <button
              onClick={selectAllDuplicates}
              className="text-sm text-accent hover:underline"
            >
              Select All Duplicates
            </button>
            <button
              onClick={clearSelection}
              className="text-sm text-gray-400 hover:text-white"
            >
              Clear Selection
            </button>
          </div>
          {selectedStats.count > 0 && (
            <div className="text-sm text-gray-400">
              Selected: {selectedStats.count} files ({formatSize(selectedStats.size)})
            </div>
          )}
        </div>

        {/* Groups list */}
        <div className="flex-1 overflow-y-auto">
          {result.groups.length === 0 ? (
            <div className="p-8 text-center text-gray-500">
              No duplicates found
            </div>
          ) : (
            <div className="divide-y divide-dark-accent">
              {result.groups.map((group) => (
                <DuplicateGroupItem
                  key={group.hash}
                  group={group}
                  isExpanded={expandedGroups.has(group.hash)}
                  selectedPaths={selectedPaths}
                  onToggleExpand={() => toggleGroup(group.hash)}
                  onToggleFile={toggleFile}
                />
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-4 py-3 border-t border-dark-accent flex-shrink-0">
          <div className="flex items-center gap-4">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="delete-mode"
                checked={toTrash}
                onChange={() => setToTrash(true)}
                className="text-accent"
              />
              Move to Trash
            </label>
            <label className="flex items-center gap-2 text-sm text-gray-400">
              <input
                type="radio"
                name="delete-mode"
                checked={!toTrash}
                onChange={() => setToTrash(false)}
                className="text-accent"
              />
              Delete Permanently
            </label>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={handleCloseAndRefresh}
              className="px-4 py-2 text-sm rounded hover:bg-dark-accent transition-colors"
            >
              Close
            </button>
            <button
              onClick={handleDelete}
              disabled={selectedPaths.size === 0 || isDeleting}
              className="px-4 py-2 text-sm bg-red-500 hover:bg-red-600 rounded font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              {isDeleting ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Deleting...
                </>
              ) : (
                <>
                  <Trash2 className="w-4 h-4" />
                  Delete Selected ({selectedStats.count})
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

interface DuplicateGroupItemProps {
  group: DuplicateGroup
  isExpanded: boolean
  selectedPaths: Set<string>
  onToggleExpand: () => void
  onToggleFile: (path: string) => void
}

function DuplicateGroupItem({
  group,
  isExpanded,
  selectedPaths,
  onToggleExpand,
  onToggleFile,
}: DuplicateGroupItemProps) {
  const wastedSize = group.size * (group.files.length - 1)

  return (
    <div>
      {/* Group header */}
      <button
        onClick={onToggleExpand}
        className="w-full px-4 py-3 flex items-center gap-3 hover:bg-dark-accent/30 transition-colors text-left"
      >
        {isExpanded ? (
          <ChevronDown className="w-4 h-4 text-gray-500" />
        ) : (
          <ChevronRight className="w-4 h-4 text-gray-500" />
        )}

        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium">
            {group.files.length} copies of {formatSize(group.size)} file
          </div>
          <div className="text-xs text-gray-500">
            Wasting {formatSize(wastedSize)}
          </div>
        </div>

        <div className="text-xs text-gray-500 font-mono">{group.hash.slice(0, 8)}...</div>
      </button>

      {/* Expanded files */}
      {isExpanded && (
        <div className="bg-dark-bg/30">
          {group.files.map((file, index) => {
            const isOriginal = index === 0
            const isSelected = selectedPaths.has(file.path)

            return (
              <div
                key={file.path}
                className="flex items-center gap-3 px-4 py-2 pl-12 hover:bg-dark-accent/20 transition-colors"
              >
                {/* Checkbox or KEEP badge */}
                {isOriginal ? (
                  <span className="w-5 h-5 flex items-center justify-center text-xs bg-green-500/20 text-green-400 rounded font-medium">
                    K
                  </span>
                ) : (
                  <button
                    onClick={() => onToggleFile(file.path)}
                    className={`w-5 h-5 rounded border flex items-center justify-center transition-colors ${
                      isSelected
                        ? 'bg-accent border-accent'
                        : 'border-gray-500 hover:border-gray-400'
                    }`}
                  >
                    {isSelected && <Check className="w-3 h-3 text-white" />}
                  </button>
                )}

                <File className="w-4 h-4 text-gray-400 flex-shrink-0" />

                <div className="flex-1 min-w-0">
                  <div className="text-sm truncate" title={file.path}>
                    {file.path}
                  </div>
                  <div className="text-xs text-gray-500">
                    Modified: {new Date(file.modified * 1000).toLocaleDateString()}
                    {isOriginal && <span className="ml-2 text-green-400">(Oldest - Keep)</span>}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
