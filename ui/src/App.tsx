import { useState, useEffect, useCallback, useRef } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { open, save } from '@tauri-apps/plugin-dialog'
import { Header } from './components/Header'
import { Sunburst } from './components/Sunburst'
import { TreemapCanvas } from './components/TreemapCanvas'
import { IcicleCanvas } from './components/IcicleCanvas'
import { BarChartCanvas } from './components/BarChartCanvas'
import { CirclePacking } from './components/CirclePacking'
import { FileTree } from './components/FileTree'
import { StatusBar } from './components/StatusBar'
import { SSHConnectionList } from './components/SSHConnectionList'
import { SSHConnectionModal } from './components/SSHConnectionModal'
import { FilterBar } from './components/FilterBar'
import { DuplicateScanModal } from './components/DuplicateScanModal'
import { DuplicateResults } from './components/DuplicateResults'
import { useSSHConnections } from './hooks/useSSHConnections'
import { useFilters } from './hooks/useFilters'
import { useSearch } from './hooks/useSearch'
import { SearchResult } from './utils/search'
import { FileNode, ScanResult, DiskInfo, SSHConnection, DuplicateScanResult, formatSize } from './types'

type VisualizationType = 'treemap' | 'sunburst' | 'icicle' | 'barchart' | 'circles'

interface ScanProgress {
  files_found?: number
  files_scanned?: number
  total_files?: number
  current_path: string
  bytes_scanned?: number
  percent?: number
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

  // SSH state
  const [isRemote, setIsRemote] = useState(false)
  const [activeConnection, setActiveConnection] = useState<SSHConnection | null>(null)
  const [sshModalOpen, setSshModalOpen] = useState(false)
  const [editingConnection, setEditingConnection] = useState<SSHConnection | null>(null)
  const [sshSidebarCollapsed, setSshSidebarCollapsed] = useState(() => {
    const saved = localStorage.getItem('data-x-ssh-sidebar-collapsed')
    return saved === 'true'
  })

  // Duplicate detection state
  const [duplicateModalOpen, setDuplicateModalOpen] = useState(false)
  const [duplicateResult, setDuplicateResult] = useState<DuplicateScanResult | null>(null)

  const {
    connections,
    isLoading: sshLoading,
    saveConnection,
    updateConnection,
    deleteConnection,
    testConnection,
  } = useSSHConnections()

  // Filters
  const {
    filters,
    filteredData,
    stats: filterStats,
    activeFilterCount,
    setSizeFilter,
    toggleTypeFilter,
    setAgeFilter,
    clearFilters,
  } = useFilters(currentNode)

  // Search
  const search = useSearch(scanResult?.root || null)

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

  // Scan a directory (local)
  const scanDirectory = useCallback(async (path: string) => {
    setIsScanning(true)
    setError(null)
    setCurrentPath(path)
    setScanProgress(null)
    setIsRemote(false)
    setActiveConnection(null)

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

  // Scan a remote directory via SSH
  const scanRemote = useCallback(async (connection: SSHConnection, path?: string) => {
    setIsScanning(true)
    setError(null)
    setIsRemote(true)
    setActiveConnection(connection)
    setCurrentPath(path || connection.default_path || '/')
    setScanProgress(null)

    try {
      const result = await invoke<ScanResult>('scan_remote', {
        connectionId: connection.id,
        path: path || connection.default_path,
      })
      setScanResult(result)
      setCurrentNode(result.root)
      setHistory([result.root])
      setSelectedNode(null)
      setDiskInfo(null) // No disk info for remote
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

  // SSH handlers
  const handleSshConnect = useCallback((connection: SSHConnection) => {
    scanRemote(connection)
  }, [scanRemote])

  const handleSshEdit = useCallback((connection: SSHConnection) => {
    setEditingConnection(connection)
    setSshModalOpen(true)
  }, [])

  const handleSshDelete = useCallback(async (connection: SSHConnection) => {
    if (confirm(`Delete connection "${connection.name}"?`)) {
      await deleteConnection(connection.id)
    }
  }, [deleteConnection])

  const handleSshAddNew = useCallback(() => {
    setEditingConnection(null)
    setSshModalOpen(true)
  }, [])

  const handleSshSidebarToggle = useCallback(() => {
    setSshSidebarCollapsed(prev => {
      const newValue = !prev
      localStorage.setItem('data-x-ssh-sidebar-collapsed', String(newValue))
      return newValue
    })
  }, [])

  const handleSshSave = useCallback(async (input: any) => {
    if (editingConnection) {
      return await updateConnection({ ...input, id: editingConnection.id })
    } else {
      return await saveConnection(input)
    }
  }, [editingConnection, updateConnection, saveConnection])

  const handleRefresh = useCallback(() => {
    if (isRemote && activeConnection) {
      scanRemote(activeConnection, currentPath)
    } else if (currentPath) {
      scanDirectory(currentPath)
    }
  }, [isRemote, activeConnection, currentPath, scanRemote, scanDirectory])

  // Handle search result selection - navigate to parent and select the file
  const handleSearchSelect = useCallback((result: SearchResult) => {
    // Find the parent node by traversing the path
    const findNodeByPath = (root: FileNode, pathParts: string[]): FileNode | null => {
      if (pathParts.length === 0) return root

      const [first, ...rest] = pathParts
      if (!root.children) return null

      const child = root.children.find(c => c.name === first)
      if (!child) return null

      return rest.length === 0 ? child : findNodeByPath(child, rest)
    }

    if (!scanResult?.root) return

    // Parse the parent path to find the parent folder
    const parentParts = result.parentPath ? result.parentPath.split('/').filter(Boolean) : []
    const parentNode = findNodeByPath(scanResult.root, parentParts)

    if (parentNode) {
      // Navigate to parent folder
      setCurrentNode(parentNode)
      setHistory(() => {
        // Build path from root to parent
        const newHistory: FileNode[] = [scanResult.root]
        let current = scanResult.root
        for (const part of parentParts) {
          const child = current.children?.find(c => c.name === part)
          if (child && child.is_dir) {
            newHistory.push(child)
            current = child
          }
        }
        return newHistory
      })
      // Select the found node
      setSelectedNode(result.node)
    }

    // Clear search
    search.clearSearch()
  }, [scanResult, search])

  // Handle duplicate scan completion
  const handleDuplicateScanComplete = useCallback((result: DuplicateScanResult) => {
    setDuplicateResult(result)
  }, [])

  // Handle export to CSV
  const handleExport = useCallback(async () => {
    if (!currentNode) return

    const date = new Date().toISOString().slice(0, 10)
    const defaultName = `data-x-export-${date}.csv`

    const filePath = await save({
      defaultPath: defaultName,
      filters: [{ name: 'CSV', extensions: ['csv'] }],
    })

    if (!filePath) return

    // Collect all files recursively
    const collectFiles = (node: FileNode, parentPath: string): string[] => {
      const lines: string[] = []
      const fullPath = parentPath ? `${parentPath}/${node.name}` : node.name

      // CSV row: path, name, size_bytes, size_human, extension, is_directory
      const row = [
        `"${fullPath.replace(/"/g, '""')}"`,
        `"${node.name.replace(/"/g, '""')}"`,
        node.size,
        `"${formatSize(node.size)}"`,
        node.extension ? `"${node.extension}"` : '""',
        node.is_dir ? 'true' : 'false',
      ].join(',')

      lines.push(row)

      if (node.children) {
        for (const child of node.children) {
          lines.push(...collectFiles(child, fullPath))
        }
      }

      return lines
    }

    const header = 'path,name,size_bytes,size_human,extension,is_directory'
    const rows = collectFiles(currentNode, '')
    const csvContent = '\ufeff' + header + '\n' + rows.join('\n') // BOM for Excel

    try {
      // Write using Tauri fs API
      const { writeTextFile } = await import('@tauri-apps/plugin-fs')
      await writeTextFile(filePath, csvContent)
      setError(null)
    } catch (e) {
      setError(`Export failed: ${e}`)
    }
  }, [currentNode])

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Only handle if not in an input field (except for Escape)
      const target = e.target as HTMLElement
      const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA'

      if (e.metaKey || e.ctrlKey) {
        switch (e.key.toLowerCase()) {
          case 'f':
            // Focus search input
            e.preventDefault()
            const searchInput = document.querySelector('input[placeholder="Search files..."]') as HTMLInputElement
            if (searchInput) searchInput.focus()
            break
          case 'e':
            // Export to CSV
            if (!isInput && currentPath) {
              e.preventDefault()
              handleExport()
            }
            break
          case 'd':
            // Find duplicates
            if (!isInput && currentPath && !isRemote) {
              e.preventDefault()
              setDuplicateModalOpen(true)
            }
            break
        }
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [currentPath, isRemote, handleExport])

  return (
    <div className="h-screen flex flex-col bg-dark-bg">
      <Header
        currentPath={currentPath}
        canGoBack={history.length > 1}
        onOpenFolder={openFolder}
        onGoBack={goBack}
        onGoToRoot={goToRoot}
        onRefresh={handleRefresh}
        onFindDuplicates={() => setDuplicateModalOpen(true)}
        onExport={handleExport}
        isRemote={isRemote}
        remoteName={activeConnection?.name}
        searchProps={scanResult ? {
          query: search.query,
          results: search.results,
          isOpen: search.isOpen,
          selectedIndex: search.selectedIndex,
          isSearching: search.isSearching,
          noResults: search.noResults,
          onQueryChange: search.handleQueryChange,
          onClear: search.clearSearch,
          onClose: search.closeDropdown,
          onKeyDown: search.handleKeyDown,
          onSelectResult: handleSearchSelect,
          setSelectedIndex: search.setSelectedIndex,
        } : undefined}
      />

      <main className="flex-1 flex overflow-hidden">
        {/* SSH Connections sidebar - FAR LEFT */}
        <aside className={`${sshSidebarCollapsed ? 'w-12' : 'w-56'} border-r border-dark-accent bg-dark-panel overflow-hidden flex flex-col flex-shrink-0 transition-all duration-200`}>
          <SSHConnectionList
            connections={connections}
            isLoading={sshLoading}
            isCollapsed={sshSidebarCollapsed}
            onConnect={handleSshConnect}
            onEdit={handleSshEdit}
            onDelete={handleSshDelete}
            onAddNew={handleSshAddNew}
            onToggleCollapse={handleSshSidebarToggle}
          />
        </aside>

        {/* File tree sidebar - LEFT */}
        {currentNode && (
          <aside className="w-64 border-r border-dark-accent bg-dark-panel overflow-hidden flex flex-col">
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

          {/* Filter bar */}
          {currentNode && !isScanning && (
            <FilterBar
              sizeFilter={filters.size}
              typeFilter={filters.types}
              ageFilter={filters.age}
              onSizeChange={setSizeFilter}
              onTypeToggle={toggleTypeFilter}
              onAgeChange={setAgeFilter}
              onClearAll={clearFilters}
              activeFilterCount={activeFilterCount}
              stats={filterStats}
            />
          )}

          {/* Visualization content */}
          <div ref={containerRef} className="flex-1 flex items-center justify-center p-4 overflow-auto">
            {isScanning ? (
              <div className="text-center max-w-md">
                <div className="animate-spin w-16 h-16 border-4 border-accent border-t-transparent rounded-full mx-auto mb-4" />
                <p className="text-lg text-gray-300 mb-2">Scanning...</p>
                {scanProgress && (
                  <div className="space-y-2">
                    <p className="text-sm text-gray-400">
                      {(scanProgress.files_scanned ?? scanProgress.files_found ?? 0).toLocaleString()} files found
                    </p>
                    {scanProgress.bytes_scanned && (
                      <p className="text-xs text-gray-500">
                        {formatSize(scanProgress.bytes_scanned)} scanned
                      </p>
                    )}
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
                    data={filteredData || currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'sunburst' && (
                  <Sunburst
                    data={filteredData || currentNode}
                    size={Math.min(containerSize.width, containerSize.height)}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'icicle' && (
                  <IcicleCanvas
                    data={filteredData || currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'barchart' && (
                  <BarChartCanvas
                    data={filteredData || currentNode}
                    width={containerSize.width}
                    height={containerSize.height}
                    selectedNode={selectedNode}
                    onSelect={setSelectedNode}
                    onDrillDown={navigateTo}
                  />
                )}
                {visualization === 'circles' && (
                  <CirclePacking
                    data={filteredData || currentNode}
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
        isRemote={isRemote}
        remoteName={activeConnection?.name}
      />

      {/* SSH Connection Modal */}
      <SSHConnectionModal
        isOpen={sshModalOpen}
        onClose={() => {
          setSshModalOpen(false)
          setEditingConnection(null)
        }}
        connection={editingConnection}
        onSave={handleSshSave}
        onTest={testConnection}
      />

      {/* Duplicate Scan Modal */}
      <DuplicateScanModal
        isOpen={duplicateModalOpen}
        onClose={() => setDuplicateModalOpen(false)}
        currentPath={currentPath}
        onScanComplete={handleDuplicateScanComplete}
      />

      {/* Duplicate Results Modal */}
      {duplicateResult && (
        <DuplicateResults
          isOpen={!!duplicateResult}
          onClose={() => setDuplicateResult(null)}
          result={duplicateResult}
          onRefresh={handleRefresh}
        />
      )}
    </div>
  )
}

export default App
