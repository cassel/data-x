import { useRef, useEffect } from 'react'
import { Search, X, Loader2, Folder, File } from 'lucide-react'
import { SearchResult, highlightMatch } from '../utils/search'
import { formatSize } from '../types'

interface SearchInputProps {
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

export function SearchInput({
  query,
  results,
  isOpen,
  selectedIndex,
  isSearching,
  noResults,
  onQueryChange,
  onClear,
  onClose,
  onKeyDown,
  onSelectResult,
  setSelectedIndex,
}: SearchInputProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)

  // Close on click outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(e.target as Node) &&
        inputRef.current &&
        !inputRef.current.contains(e.target as Node)
      ) {
        onClose()
      }
    }

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside)
      return () => document.removeEventListener('mousedown', handleClickOutside)
    }
  }, [isOpen, onClose])

  // Handle key down with result selection
  const handleKeyDown = (e: React.KeyboardEvent) => {
    const result = onKeyDown(e)
    if (result && e.key === 'Enter') {
      onSelectResult(result)
      onClose()
    }
  }

  return (
    <div className="relative">
      {/* Search input */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          onKeyDown={handleKeyDown}
          onFocus={() => {
            if (results.length > 0) {
              // Re-open if we have results
            }
          }}
          placeholder="Search files..."
          className="w-64 pl-9 pr-8 py-1.5 bg-dark-bg border border-dark-accent rounded-md text-sm focus:outline-none focus:border-accent placeholder-gray-500"
        />
        {query && (
          <button
            onClick={onClear}
            className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded hover:bg-dark-accent transition-colors"
          >
            {isSearching ? (
              <Loader2 className="w-4 h-4 text-gray-500 animate-spin" />
            ) : (
              <X className="w-4 h-4 text-gray-500" />
            )}
          </button>
        )}
      </div>

      {/* Dropdown */}
      {isOpen && (results.length > 0 || noResults) && (
        <div
          ref={dropdownRef}
          className="absolute top-full left-0 right-0 mt-1 bg-dark-panel border border-dark-accent rounded-md shadow-xl z-50 overflow-hidden"
        >
          {noResults ? (
            <div className="px-4 py-3 text-sm text-gray-500 text-center">
              No files found for "{query}"
            </div>
          ) : (
            <ul className="py-1 max-h-80 overflow-y-auto">
              {results.map((result, index) => (
                <li key={result.node.id}>
                  <button
                    onClick={() => {
                      onSelectResult(result)
                      onClose()
                    }}
                    onMouseEnter={() => setSelectedIndex(index)}
                    className={`w-full px-3 py-2 flex items-start gap-3 text-left transition-colors ${
                      index === selectedIndex
                        ? 'bg-accent/20'
                        : 'hover:bg-dark-accent/50'
                    }`}
                  >
                    {/* Icon */}
                    <div className="flex-shrink-0 mt-0.5">
                      {result.node.is_dir ? (
                        <Folder className="w-4 h-4 text-accent" />
                      ) : (
                        <File className="w-4 h-4 text-gray-400" />
                      )}
                    </div>

                    {/* Content */}
                    <div className="flex-1 min-w-0">
                      {/* Filename with highlight */}
                      <div className="text-sm truncate">
                        {highlightMatch(
                          result.node.name,
                          result.matchStart,
                          result.matchEnd
                        ).map((segment, i) => (
                          <span
                            key={i}
                            className={segment.isMatch ? 'text-accent font-medium' : ''}
                          >
                            {segment.text}
                          </span>
                        ))}
                      </div>

                      {/* Parent path */}
                      <div className="text-xs text-gray-500 truncate">
                        {result.parentPath || '/'}
                      </div>
                    </div>

                    {/* Size */}
                    <div className="flex-shrink-0 text-xs text-gray-500">
                      {formatSize(result.node.size)}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {/* Footer hint */}
          {results.length > 0 && (
            <div className="px-3 py-2 border-t border-dark-accent text-xs text-gray-500 flex items-center gap-4">
              <span>
                <kbd className="px-1.5 py-0.5 bg-dark-accent rounded text-xs">↑↓</kbd> navigate
              </span>
              <span>
                <kbd className="px-1.5 py-0.5 bg-dark-accent rounded text-xs">Enter</kbd> select
              </span>
              <span>
                <kbd className="px-1.5 py-0.5 bg-dark-accent rounded text-xs">Esc</kbd> close
              </span>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
