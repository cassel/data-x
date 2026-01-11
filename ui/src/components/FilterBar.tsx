import { Filter, HardDrive, FileType, Calendar, X } from 'lucide-react'
import { FilterDropdown } from './FilterDropdown'
import { SizeFilter, AgeFilter, FileType as FileTypeValue } from '../utils/filters'
import { formatSize } from '../types'

interface FilterBarProps {
  sizeFilter: SizeFilter
  typeFilter: FileTypeValue[]
  ageFilter: AgeFilter
  onSizeChange: (size: SizeFilter) => void
  onTypeToggle: (type: FileTypeValue) => void
  onAgeChange: (age: AgeFilter) => void
  onClearAll: () => void
  activeFilterCount: number
  stats: {
    originalFiles: number
    originalSize: number
    filteredFiles: number
    filteredSize: number
  } | null
}

const SIZE_OPTIONS = [
  { value: 'all', label: 'All sizes' },
  { value: '100mb', label: '> 100 MB' },
  { value: '1gb', label: '> 1 GB' },
  { value: '10gb', label: '> 10 GB' },
]

const TYPE_OPTIONS = [
  { value: 'videos', label: 'Videos' },
  { value: 'images', label: 'Images' },
  { value: 'audio', label: 'Audio' },
  { value: 'documents', label: 'Documents' },
  { value: 'code', label: 'Code' },
  { value: 'archives', label: 'Archives' },
  { value: 'other', label: 'Other' },
]

const AGE_OPTIONS = [
  { value: 'all', label: 'Any age' },
  { value: '1month', label: '> 1 month' },
  { value: '6months', label: '> 6 months' },
  { value: '1year', label: '> 1 year' },
]

export function FilterBar({
  sizeFilter,
  typeFilter,
  ageFilter,
  onSizeChange,
  onTypeToggle,
  onAgeChange,
  onClearAll,
  activeFilterCount,
  stats,
}: FilterBarProps) {
  const isFiltered = activeFilterCount > 0

  return (
    <div className="flex items-center gap-3 px-4 py-2 bg-dark-panel/50 border-b border-dark-accent">
      {/* Filter icon and label */}
      <div className="flex items-center gap-2 text-gray-400">
        <Filter className="w-4 h-4" />
        <span className="text-xs uppercase tracking-wider">Filters</span>
        {activeFilterCount > 0 && (
          <span className="px-1.5 py-0.5 bg-accent text-white text-xs rounded-full">
            {activeFilterCount}
          </span>
        )}
      </div>

      <div className="w-px h-6 bg-dark-accent" />

      {/* Size filter */}
      <FilterDropdown
        label="Size"
        options={SIZE_OPTIONS}
        value={sizeFilter}
        onChange={(v) => onSizeChange(v as SizeFilter)}
        icon={<HardDrive className="w-4 h-4" />}
      />

      {/* Type filter */}
      <FilterDropdown
        label="Type"
        options={TYPE_OPTIONS}
        value={typeFilter}
        onToggle={(v) => onTypeToggle(v as FileTypeValue)}
        multiSelect
        icon={<FileType className="w-4 h-4" />}
      />

      {/* Age filter */}
      <FilterDropdown
        label="Age"
        options={AGE_OPTIONS}
        value={ageFilter}
        onChange={(v) => onAgeChange(v as AgeFilter)}
        icon={<Calendar className="w-4 h-4" />}
      />

      {/* Clear all button */}
      {isFiltered && (
        <button
          onClick={onClearAll}
          className="flex items-center gap-1 px-2 py-1 text-xs text-gray-400 hover:text-white hover:bg-dark-accent rounded transition-colors"
        >
          <X className="w-3 h-3" />
          Clear all
        </button>
      )}

      {/* Spacer */}
      <div className="flex-1" />

      {/* Results counter */}
      {stats && (
        <div className="text-xs text-gray-400">
          {isFiltered ? (
            <span>
              <span className="text-accent font-medium">{stats.filteredFiles.toLocaleString()}</span>
              {' of '}
              {stats.originalFiles.toLocaleString()} files
              {' '}
              <span className="text-gray-500">
                ({formatSize(stats.filteredSize)} of {formatSize(stats.originalSize)})
              </span>
            </span>
          ) : (
            <span>
              {stats.originalFiles.toLocaleString()} files ({formatSize(stats.originalSize)})
            </span>
          )}
        </div>
      )}
    </div>
  )
}
