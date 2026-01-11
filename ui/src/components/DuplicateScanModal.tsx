import { useState, useEffect } from 'react'
import { X, Search, Loader2, AlertCircle } from 'lucide-react'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { DuplicateScanResult, DuplicateScanProgress } from '../types'

interface DuplicateScanModalProps {
  isOpen: boolean
  onClose: () => void
  currentPath: string
  onScanComplete: (result: DuplicateScanResult) => void
}

const SIZE_OPTIONS = [
  { value: 0, label: 'All files' },
  { value: 1024, label: '>1 KB' },
  { value: 1024 * 100, label: '>100 KB' },
  { value: 1024 * 1024, label: '>1 MB' },
  { value: 1024 * 1024 * 10, label: '>10 MB' },
]

export function DuplicateScanModal({
  isOpen,
  onClose,
  currentPath,
  onScanComplete,
}: DuplicateScanModalProps) {
  const [minSize, setMinSize] = useState(1024) // Default 1KB
  const [includeHidden, setIncludeHidden] = useState(false)
  const [isScanning, setIsScanning] = useState(false)
  const [progress, setProgress] = useState<DuplicateScanProgress | null>(null)
  const [error, setError] = useState<string | null>(null)

  // Reset state when modal opens
  useEffect(() => {
    if (isOpen) {
      setError(null)
      setProgress(null)
    }
  }, [isOpen])

  // Listen for progress events
  useEffect(() => {
    if (!isScanning) return

    const unlisten = listen<DuplicateScanProgress>('duplicate-scan-progress', (event) => {
      setProgress(event.payload)
    })

    return () => {
      unlisten.then((fn) => fn())
    }
  }, [isScanning])

  const handleStartScan = async () => {
    setIsScanning(true)
    setError(null)
    setProgress(null)

    try {
      const result = await invoke<DuplicateScanResult>('find_duplicates', {
        path: currentPath,
        minSize: minSize > 0 ? minSize : null,
        includeHidden,
      })

      onScanComplete(result)
      onClose()
    } catch (e) {
      setError(String(e))
    } finally {
      setIsScanning(false)
    }
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-dark-panel border border-dark-accent rounded-lg w-full max-w-md shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-dark-accent">
          <h2 className="font-semibold flex items-center gap-2">
            <Search className="w-5 h-5 text-accent" />
            Find Duplicates
          </h2>
          <button
            onClick={onClose}
            disabled={isScanning}
            className="p-1 rounded hover:bg-dark-accent transition-colors disabled:opacity-50"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="p-4 space-y-4">
          {/* Path */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">Scan Path</label>
            <div className="text-sm bg-dark-bg rounded px-3 py-2 truncate" title={currentPath}>
              {currentPath}
            </div>
          </div>

          {/* Minimum size */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">Minimum File Size</label>
            <select
              value={minSize}
              onChange={(e) => setMinSize(Number(e.target.value))}
              disabled={isScanning}
              className="w-full bg-dark-bg border border-dark-accent rounded px-3 py-2 text-sm focus:outline-none focus:border-accent disabled:opacity-50"
            >
              {SIZE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
            <p className="text-xs text-gray-500 mt-1">
              Skip files smaller than this size to speed up scanning
            </p>
          </div>

          {/* Include hidden */}
          <div className="flex items-center gap-3">
            <input
              type="checkbox"
              id="include-hidden"
              checked={includeHidden}
              onChange={(e) => setIncludeHidden(e.target.checked)}
              disabled={isScanning}
              className="w-4 h-4 rounded bg-dark-bg border-dark-accent focus:ring-accent"
            />
            <label htmlFor="include-hidden" className="text-sm">
              Include hidden files
            </label>
          </div>

          {/* Progress */}
          {isScanning && progress && (
            <div className="bg-dark-bg rounded p-3 space-y-2">
              <div className="flex items-center gap-2 text-sm">
                <Loader2 className="w-4 h-4 animate-spin text-accent" />
                <span>{progress.phase}</span>
              </div>

              {progress.total_files > 0 && (
                <>
                  <div className="w-full h-2 bg-dark-accent rounded-full overflow-hidden">
                    <div
                      className="h-full bg-accent transition-all duration-200"
                      style={{
                        width: `${Math.min(
                          (progress.files_processed / progress.total_files) * 100,
                          100
                        )}%`,
                      }}
                    />
                  </div>
                  <div className="text-xs text-gray-500">
                    {progress.files_processed.toLocaleString()} /{' '}
                    {progress.total_files.toLocaleString()} files
                  </div>
                </>
              )}

              {progress.current_file && (
                <div className="text-xs text-gray-600 truncate" title={progress.current_file}>
                  {progress.current_file.length > 50
                    ? '...' + progress.current_file.slice(-47)
                    : progress.current_file}
                </div>
              )}
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="bg-red-500/10 border border-red-500/30 rounded p-3 flex items-start gap-2">
              <AlertCircle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-sm text-red-300">{error}</p>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 px-4 py-3 border-t border-dark-accent">
          <button
            onClick={onClose}
            disabled={isScanning}
            className="px-4 py-2 text-sm rounded hover:bg-dark-accent transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleStartScan}
            disabled={isScanning}
            className="px-4 py-2 text-sm bg-accent hover:bg-accent-light rounded font-medium transition-colors disabled:opacity-50 flex items-center gap-2"
          >
            {isScanning ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                Scanning...
              </>
            ) : (
              <>
                <Search className="w-4 h-4" />
                Start Scan
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  )
}
