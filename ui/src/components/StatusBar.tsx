import { FileNode, ScanResult, DiskInfo, formatSize } from '../types'
import { HardDrive, File, Clock, AlertCircle } from 'lucide-react'

interface StatusBarProps {
  scanResult: ScanResult | null
  diskInfo: DiskInfo | null
  selectedNode: FileNode | null
  isScanning: boolean
  error: string | null
}

export function StatusBar({
  scanResult,
  diskInfo,
  selectedNode,
  isScanning,
  error,
}: StatusBarProps) {
  const diskPercent = diskInfo
    ? Math.round((diskInfo.used / diskInfo.total) * 100)
    : 0

  return (
    <footer className="h-8 bg-dark-panel border-t border-dark-accent flex items-center px-4 gap-6 text-xs">
      {/* Error message */}
      {error && (
        <div className="flex items-center gap-2 text-red-400">
          <AlertCircle className="w-3.5 h-3.5" />
          <span className="truncate">{error}</span>
        </div>
      )}

      {/* Scanning status */}
      {isScanning && !error && (
        <div className="flex items-center gap-2 text-accent">
          <div className="animate-spin w-3.5 h-3.5 border-2 border-accent border-t-transparent rounded-full" />
          <span>Scanning...</span>
        </div>
      )}

      {/* Scan result */}
      {scanResult && !isScanning && !error && (
        <>
          <div className="flex items-center gap-2 text-gray-400">
            <File className="w-3.5 h-3.5" />
            <span>{scanResult.total_files.toLocaleString()} files</span>
          </div>

          <div className="flex items-center gap-2 text-gray-400">
            <HardDrive className="w-3.5 h-3.5" />
            <span>{formatSize(scanResult.total_size)}</span>
          </div>

          <div className="flex items-center gap-2 text-gray-400">
            <Clock className="w-3.5 h-3.5" />
            <span>{scanResult.scan_time_ms}ms</span>
          </div>
        </>
      )}

      {/* Spacer */}
      <div className="flex-1" />

      {/* Selected node info */}
      {selectedNode && (
        <div className="text-gray-400 truncate max-w-xs">
          {selectedNode.name} - {formatSize(selectedNode.size)}
        </div>
      )}

      {/* Disk usage */}
      {diskInfo && (
        <div className="flex items-center gap-2">
          <div className="w-24 h-2 bg-dark-accent rounded-full overflow-hidden">
            <div
              className={`h-full transition-all ${
                diskPercent > 90 ? 'bg-red-500' : diskPercent > 70 ? 'bg-yellow-500' : 'bg-accent'
              }`}
              style={{ width: `${diskPercent}%` }}
            />
          </div>
          <span className="text-gray-400">
            {formatSize(diskInfo.used)} / {formatSize(diskInfo.total)}
          </span>
        </div>
      )}
    </footer>
  )
}
