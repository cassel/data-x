import { useState } from 'react'
import { ChevronLeft, FolderOpen, Home, RefreshCw, Settings, HelpCircle, Keyboard, Terminal, Mail, Globe, Copy, Download } from 'lucide-react'
import { invoke } from '@tauri-apps/api/core'
import { Modal } from './Modal'
import { SearchInput } from './SearchInput'
import { SearchResult } from '../utils/search'

interface SearchProps {
  query: string
  results: SearchResult[]
  isOpen: boolean
  selectedIndex: number
  isSearching: boolean
  noResults: boolean
  onQueryChange: (query: string) => void
  onClear: () => void
  onClose: () => void
  onKeyDown: (e: React.KeyboardEvent) => SearchResult | null | undefined
  onSelectResult: (result: SearchResult) => void
  setSelectedIndex: (index: number) => void
}

interface HeaderProps {
  currentPath: string
  canGoBack: boolean
  onOpenFolder: () => void
  onGoBack: () => void
  onGoToRoot: () => void
  onRefresh: () => void
  onFindDuplicates?: () => void
  onExport?: () => void
  isRemote?: boolean
  remoteName?: string
  searchProps?: SearchProps
}

export function Header({
  currentPath,
  canGoBack,
  onOpenFolder,
  onGoBack,
  onGoToRoot,
  onRefresh,
  onFindDuplicates,
  onExport,
  isRemote = false,
  remoteName,
  searchProps,
}: HeaderProps) {
  const [showHelp, setShowHelp] = useState(false)
  const [showSettings, setShowSettings] = useState(false)

  return (
    <>
      <header className="h-12 bg-dark-panel border-b border-dark-accent flex items-center px-4 gap-2">
        {/* Navigation buttons */}
        <div className="flex items-center gap-1">
          <button
            onClick={onGoBack}
            disabled={!canGoBack}
            className="p-2 rounded hover:bg-dark-accent disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Go back"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>

          <button
            onClick={onGoToRoot}
            disabled={!currentPath}
            className="p-2 rounded hover:bg-dark-accent disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Go to root"
          >
            <Home className="w-5 h-5" />
          </button>
        </div>

        <div className="w-px h-6 bg-dark-accent mx-2" />

        {/* Open folder button */}
        <button
          onClick={onOpenFolder}
          className="flex items-center gap-2 px-3 py-1.5 rounded bg-accent hover:bg-accent-light transition-colors font-medium"
        >
          <FolderOpen className="w-4 h-4" />
          <span>Open</span>
        </button>

        {/* Refresh button */}
        <button
          onClick={onRefresh}
          disabled={!currentPath}
          className="p-2 rounded hover:bg-dark-accent disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          title="Refresh"
        >
          <RefreshCw className="w-5 h-5" />
        </button>

        <div className="w-px h-6 bg-dark-accent mx-2" />

        {/* Find Duplicates button */}
        {onFindDuplicates && (
          <button
            onClick={onFindDuplicates}
            disabled={!currentPath || isRemote}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded text-sm hover:bg-dark-accent disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title={isRemote ? "Not available for remote scans" : "Find duplicate files"}
          >
            <Copy className="w-4 h-4" />
            <span className="hidden sm:inline">Duplicates</span>
          </button>
        )}

        {/* Export button */}
        {onExport && (
          <button
            onClick={onExport}
            disabled={!currentPath}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded text-sm hover:bg-dark-accent disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Export to CSV"
          >
            <Download className="w-4 h-4" />
            <span className="hidden sm:inline">Export</span>
          </button>
        )}

        {/* Current path */}
        <div className="flex-1 px-4">
          <div className="flex items-center gap-2">
            {isRemote && (
              <span className="flex items-center gap-1 px-2 py-0.5 bg-accent/20 text-accent rounded text-xs">
                <Globe className="w-3 h-3" />
                {remoteName || 'Remote'}
              </span>
            )}
            <p className="text-sm text-gray-400 truncate" title={currentPath}>
              {currentPath || 'No folder selected'}
            </p>
          </div>
        </div>

        {/* Search input */}
        {searchProps && (
          <SearchInput
            query={searchProps.query}
            results={searchProps.results}
            isOpen={searchProps.isOpen}
            selectedIndex={searchProps.selectedIndex}
            isSearching={searchProps.isSearching}
            noResults={searchProps.noResults}
            onQueryChange={searchProps.onQueryChange}
            onClear={searchProps.onClear}
            onClose={searchProps.onClose}
            onKeyDown={searchProps.onKeyDown}
            onSelectResult={searchProps.onSelectResult}
            setSelectedIndex={searchProps.setSelectedIndex}
          />
        )}

        {/* Right side buttons */}
        <div className="flex items-center gap-1">
          <button
            onClick={async () => {
              try {
                await invoke('open_in_terminal', { path: currentPath || null })
              } catch (e) {
                console.error('Failed to open terminal:', e)
              }
            }}
            className="p-2 rounded hover:bg-dark-accent transition-colors group"
            title="Open in Terminal (TUI mode)"
          >
            <span className="font-mono text-sm font-bold text-gray-400 group-hover:text-accent transition-colors">{'>_'}</span>
          </button>

          <button
            onClick={() => setShowSettings(true)}
            className="p-2 rounded hover:bg-dark-accent transition-colors"
            title="Settings"
          >
            <Settings className="w-5 h-5" />
          </button>

          <button
            onClick={() => setShowHelp(true)}
            className="p-2 rounded hover:bg-dark-accent transition-colors"
            title="Help"
          >
            <HelpCircle className="w-5 h-5" />
          </button>
        </div>
      </header>

      {/* Help Modal */}
      <Modal title="About Data-X" isOpen={showHelp} onClose={() => setShowHelp(false)}>
        <div className="space-y-4">
          <div>
            <h3 className="font-semibold text-accent mb-1">Data-X v0.4.0</h3>
            <p className="text-sm text-gray-400">Disk space analyzer with remote scanning and discovery</p>
          </div>

          <div>
            <h4 className="font-medium mb-2">New in v0.4.0</h4>
            <ul className="text-sm text-gray-400 space-y-1 list-disc list-inside">
              <li><span className="text-gray-300">SSH Remote Scanning</span> - Connect to remote servers</li>
              <li><span className="text-gray-300">Quick Filters</span> - Filter by size, type, and age</li>
              <li><span className="text-gray-300">Search</span> - Find files instantly by name</li>
              <li><span className="text-gray-300">Duplicate Finder</span> - Find and remove duplicate files</li>
              <li><span className="text-gray-300">Export to CSV</span> - Export scan results for analysis</li>
            </ul>
          </div>

          <div>
            <h4 className="font-medium flex items-center gap-2 mb-2">
              <Keyboard className="w-4 h-4" /> Keyboard Shortcuts
            </h4>
            <div className="text-sm space-y-1 text-gray-300">
              <div className="flex justify-between">
                <span>Open folder</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+O</kbd>
              </div>
              <div className="flex justify-between">
                <span>Go back</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+[</kbd>
              </div>
              <div className="flex justify-between">
                <span>Refresh</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+R</kbd>
              </div>
              <div className="flex justify-between">
                <span>Search files</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+F</kbd>
              </div>
              <div className="flex justify-between">
                <span>Find duplicates</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+D</kbd>
              </div>
              <div className="flex justify-between">
                <span>Export to CSV</span>
                <kbd className="px-2 py-0.5 bg-dark-accent rounded text-xs">Cmd+E</kbd>
              </div>
            </div>
          </div>

          <div>
            <h4 className="font-medium mb-2">How to use</h4>
            <ul className="text-sm text-gray-400 space-y-1 list-disc list-inside">
              <li>Click on folders to drill down</li>
              <li>Right-click for context menu</li>
              <li>Switch views using the toolbar</li>
              <li>Use filters to find large/old files</li>
              <li>Add SSH connections in the left sidebar</li>
            </ul>
          </div>

          <div className="border-t border-dark-accent pt-4">
            <h4 className="font-medium flex items-center gap-2 mb-2">
              <Terminal className="w-4 h-4" /> Terminal Usage (TUI)
            </h4>
            <div className="text-sm text-gray-400 space-y-2">
              <p>Data-X also has a terminal interface:</p>
              <div className="bg-dark-accent/50 rounded p-2 font-mono text-xs space-y-1">
                <div><span className="text-gray-500">#</span> Scan local folder:</div>
                <div className="text-accent">data-x /path/to/folder</div>
                <div className="mt-2"><span className="text-gray-500">#</span> TUI mode (interactive):</div>
                <div className="text-accent">data-x --tui /path/to/folder</div>
                <div className="mt-2"><span className="text-gray-500">#</span> Remote scan via SSH:</div>
                <div className="text-accent">data-x user@host:/remote/path</div>
                <div className="mt-2"><span className="text-gray-500">#</span> JSON output:</div>
                <div className="text-accent">data-x --json /path/to/folder</div>
              </div>
            </div>
          </div>

          <div className="border-t border-dark-accent pt-4 text-center">
            <p className="text-sm text-gray-500 flex items-center justify-center gap-2">
              <Mail className="w-3.5 h-3.5" />
              Powered by <a href="mailto:c@cassel.us" className="text-accent hover:underline">C. Cassel</a>
            </p>
          </div>
        </div>
      </Modal>

      {/* Settings Modal */}
      <Modal title="Settings" isOpen={showSettings} onClose={() => setShowSettings(false)}>
        <div className="space-y-4">
          <p className="text-sm text-gray-400">Settings coming soon...</p>
          <div className="text-sm text-gray-500">
            <p>Planned features:</p>
            <ul className="list-disc list-inside mt-1">
              <li>Default visualization</li>
              <li>Show hidden files</li>
              <li>Color scheme</li>
            </ul>
          </div>
        </div>
      </Modal>
    </>
  )
}
