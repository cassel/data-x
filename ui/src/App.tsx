import { useState, useEffect, useCallback, useRef } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { open } from '@tauri-apps/plugin-dialog'
import { Header } from './components/Header'
import { Sunburst } from './components/Sunburst'
import { TreemapCanvas } from './components/TreemapCanvas'
import { IcicleCanvas } from './components/IcicleCanvas'
import { BarChartCanvas } from './components/BarChartCanvas'
import { CirclePacking } from './components/CirclePacking'
import { FileTree } from './components/FileTree'
import { StatusBar } from './components/StatusBar'
import { FileNode, ScanResult, DiskInfo, formatSize } from './types'

type VisualizationType = 'treemap' | 'sunburst' | 'icicle' | 'barchart' | 'circles'

interface ScanProgress {
  files_scanned: number
  total_files: number
  current_path: string
  bytes_scanned: number
}

const visualizationLabels: Record<VisualizationType, string> = {
  treemap: 'Treemap',
  sunburst: 'Sunburst',
  icicle: 'Icicle',
  barchart: 'Bar Chart',
  circles: 'Circles',
}

function App() {
  const [scanResult, setScanResult] = useState<ScanResult | null>(null)
  const [diskInfo, setDiskInfo] = useState<DiskInfo | null>(null)
  const [currentPath, setCurrentPath] = useState<string>('')
  const [currentNode, setCurrentNode] = useState<FileNode | null>(null)
  const [selectedNode, setSelectedNode] = useState<FileNode | null>(null)
  const [isScanning, setIsScanning] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [history, setHistory] = useState<FileNode[]>([])
  const [visualization, setVisualization] = useState<VisualizationType>('treemap')
  const [containerSize, setContainerSize] = useState({ width: 800, height: 600 })
  const [scanProgress, setScanProgress] = useState<ScanProgress | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  // Listen for scan progress events
  useEffect(() => {
    const unlisten = listen<ScanProgress>('scan-progress', (event) => {
      setScanProgress(event.payload)
    })

    return () => {
      unlisten.then(fn => fn())
    }
  }, [])

  // Track container size
  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const updateSize = () => {
      const rect = container.getBoundingClientRect()
      setContainerSize({
        width: Math.floor(rect.width) - 32, // subtract padding
        height: Math.floor(rect.height) - 32,
      })
    }

    updateSize()

    const observer = new ResizeObserver(updateSize)
    observer.observe(container)

    return () => observer.disconnect()
  }, [])

  // Scan a directory
  const scanDirectory = useCallback(async (path: string) => {
    setIsScanning(true)
    setError(null)
    setCurrentPath(path)
    setScanProgress(null)

    try {
      const result = await invoke<ScanResult>('scan_directory', { path, maxDepth: 8 })
      setScanResult(result)
      setCurrentNode(result.root)
      setHistory([result.root])
      setSelectedNode(null)

      // Get disk info
      const disk = await invoke<DiskInfo>('get_disk_info', { path })
      setDiskInfo(disk)
    } catch (e) {
      setError(String(e))
    } finally {
      setIsScanning(false)
      setScanProgress(null)
    }
  }, [])

  // Open folder dialog
  const openFolder = useCallback(async () => {
    const selected = await open({
      directory: true,
      multiple: false,
      title: 'Select folder to analyze',
    })

    if (selected) {
      scanDirectory(selected as string)
    }
  }, [scanDirectory])

  // Navigate to a node (drill down)
  const navigateTo = useCallback((node: FileNode) => {
    if (node.is_dir) {
      setCurrentNode(node)
      setHistory(prev => [...prev, node])
      setSelectedNode(null)
    }
  }, [])

  // Go back in history
  const goBack = useCallback(() => {
    if (history.length > 1) {
      const newHistory = history.slice(0, -1)
      setHistory(newHistory)
      setCurrentNode(newHistory[newHistory.length - 1])
      setSelectedNode(null)
    }
  }, [history])

  // Go to root
  const goToRoot = useCallback(() => {
    if (scanResult) {
      setCurrentNode(scanResult.root)
      setHistory([scanResult.root])
      setSelectedNode(null)
    }
  }, [scanResult])

  // Handle file actions
  const handleOpenInFinder = useCallback(async (node: FileNode) => {
    try {
      await invoke('open_in_finder', { path: node.path })
    } catch (e) {
      setError(String(e))
    }
  }, [])

  const handleMoveToTrash = useCallback(async (node: FileNode) => {
    try {
      await invoke('move_to_trash', { path: node.path })
      // Rescan after deletion
      if (currentPath) {
        scanDirectory(currentPath)
      }
    } catch (e) {
      setError(String(e))
    }
  }, [currentPath, scanDirectory])

  // Initial scan on mount - wait for user to select folder
  useEffect(() => {
    // Auto-scan disabled - user must select folder manually
  }, [])

  return (
    <div className="h-screen flex flex-col bg-dark-bg">
      <Header
        currentPath={currentPath}
        canGoBack={history.length > 1}
        onOpenFolder={openFolder}
        onGoBack={goBack}
        onGoToRoot={goToRoot}
        onRefresh={() => currentPath && scanDirectory(currentPath)}
      />

      <main className="flex-1 flex overflow-hidden">
        {/* File tree sidebar - LEFT */}
        {currentNode && (
          <aside className="w-72 border-r border-dark-accent bg-dark-panel overflow-hidden flex flex-col">
            <FileTree
              root={currentNode}
              selectedNode={selectedNode}
              onSelect={setSelectedNode}
              onDrillDown={navigateTo}
              onOpenInFinder={handleOpenInFinder}
              onMoveToTrash={handleMoveToTrash}
            />
          </aside>
        )}

        {/* Visualization area */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Visualization selector */}
          {currentNode && !isScanning && (
            <div className="flex items-center gap-2 px-4 py-2 border-b border-dark-accent bg-dark-panel/50">
              <span className="text-xs text-gray-500 uppercase tracking-wider mr-2">View:</span>
              {(Object.keys(visualizationLabels) as VisualizationType[]).map((type) => (
                <button
                  key={type}
                  onClick={() => setVisualization(type)}
                  className={`px-3 py-1.5 text-xs rounded-md transition-colors ${
                    visualization === type
                      ? 'bg-accent text-white'
                      : 'bg-dark-accent/50 text-gray-400 hover:bg-dark-accent hover:text-white'
                  }`}
                >
                  {visualizationLabels[type]}
                </button>
              ))}
            </div>
          )}

          {/* Visualization content */}
          <div ref={containerRef} className="flex-1 flex items-center justify-center p-4 overflow-auto">
            {isScanning ? (
              <div className="text-center max-w-md">
                <div className="animate-spin w-16 h-16 border-4 border-accent border-t-transparent rounded-full mx-auto mb-4" />
                <p className="text-lg text-gray-300 mb-2">Scanning...</p>
                {scanProgress && (
                  <div className="space-y-2">
                    <div className="w-full h-2 bg-dark-accent rounded-full overflow-hidden">
                      <div
                        className="h-full bg-accent transition-all duration-200"
                        style={{
                          width: scanProgress.total_files > 0
                            ? `${Math.min((scanProgress.files_scanned / scanProgress.total_files) * 100, 100)}%`
                            : '0%'
                        }}
                      />
                    </div>
                    <p className="text-sm text-gray-400">
                      {scanProgress.files_scanned.toLocaleString()} / {scanProgress.total_files.toLocaleString()} files
                    </p>
                    <p className="text-xs text-gray-500">
                      {formatSize(scanProgress.bytes_scanned)} scanned
                    </p>
                    <p className="text-xs text-gray-600 truncate" title={scanProgress.current_path}>
                      {scanProgress.current_path.length > 50
                        ? '...' + scanProgress.current_path.slice(-47)
                        : scanProgress.current_path}
                    </p>
                  </div>
                )}
              </div>
            ) : currentNode ? (
              <>
                {visualization === 'treemap' && (
                  <TreemapCanvas
                    data={currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'sunburst' && (
                  <Sunburst
                    data={currentNode}
                    size={Math.min(containerSize.width, containerSize.height)}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'icicle' && (
                  <IcicleCanvas
                    data={currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'barchart' && (
                  <BarChartCanvas
                    data={currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'circles' && (
                  <CirclePacking
                    data={currentNode}
                    size={Math.min(containerSize.width, containerSize.height)}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
              </>
            ) : (
              <div className="text-center">
                <p className="text-xl text-gray-400 mb-4">No folder selected</p>
                <button
                  onClick={openFolder}
                  className="px-6 py-3 bg-accent hover:bg-accent-light rounded-lg font-medium transition-colors"
                >
                  Select Folder
                </button>
              </div>
            )}
          </div>
        </div>
      </main>

      <StatusBar
        scanResult={scanResult}
        diskInfo={diskInfo}
        selectedNode={selectedNode}
        isScanning={isScanning}
        error={error}
      />
    </div>
  )
}

export default App
