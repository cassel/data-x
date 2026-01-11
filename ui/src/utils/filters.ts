import { FileNode } from '../types'

// Size filter thresholds in bytes
export const SIZE_THRESHOLDS = {
  '100mb': 100 * 1024 * 1024,      // 104,857,600
  '1gb': 1024 * 1024 * 1024,       // 1,073,741,824
  '10gb': 10 * 1024 * 1024 * 1024, // 10,737,418,240
} as const

export type SizeFilter = 'all' | '100mb' | '1gb' | '10gb'

// Age filter thresholds in milliseconds
export const AGE_THRESHOLDS = {
  '1month': 30 * 24 * 60 * 60 * 1000,
  '6months': 6 * 30 * 24 * 60 * 60 * 1000,
  '1year': 365 * 24 * 60 * 60 * 1000,
} as const

export type AgeFilter = 'all' | '1month' | '6months' | '1year'

// File type categories
export const FILE_TYPE_MAPPING: Record<string, string[]> = {
  videos: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'],
  images: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico', 'heic', 'heif', 'tiff', 'raw'],
  audio: ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'aiff'],
  documents: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'ods', 'odp'],
  code: ['js', 'ts', 'jsx', 'tsx', 'py', 'rs', 'go', 'java', 'c', 'cpp', 'h', 'hpp', 'css', 'html', 'json', 'yaml', 'yml', 'md', 'sh', 'rb', 'php', 'swift', 'kt'],
  archives: ['zip', 'tar', 'gz', 'rar', '7z', 'bz2', 'xz', 'tgz', 'dmg', 'iso'],
}

export type FileType = keyof typeof FILE_TYPE_MAPPING | 'other'

export interface FilterState {
  size: SizeFilter
  types: FileType[]
  age: AgeFilter
}

export const DEFAULT_FILTER_STATE: FilterState = {
  size: 'all',
  types: [],
  age: 'all',
}

/**
 * Get file type from extension
 */
export function getFileType(extension: string | null): FileType {
  if (!extension) return 'other'
  const ext = extension.toLowerCase()

  for (const [type, extensions] of Object.entries(FILE_TYPE_MAPPING)) {
    if (extensions.includes(ext)) {
      return type as FileType
    }
  }
  return 'other'
}

/**
 * Check if a file matches the size filter
 */
export function matchesSizeFilter(size: number, filter: SizeFilter): boolean {
  if (filter === 'all') return true
  return size > SIZE_THRESHOLDS[filter]
}

/**
 * Check if a file matches the type filter
 */
export function matchesTypeFilter(extension: string | null, types: FileType[]): boolean {
  if (types.length === 0) return true
  const fileType = getFileType(extension)
  return types.includes(fileType)
}

/**
 * Check if a file matches the age filter (older than threshold)
 * Note: We don't have mtime in the current FileNode, so this is a placeholder
 */
export function matchesAgeFilter(mtime: number | null, filter: AgeFilter): boolean {
  if (filter === 'all') return true
  if (mtime === null) return true // Include files without mtime

  const now = Date.now()
  const fileAge = now - mtime
  return fileAge > AGE_THRESHOLDS[filter]
}

/**
 * Filter a file tree based on filter state
 * Returns a new tree with only matching files and recalculated sizes
 */
export function filterFileTree(root: FileNode, filters: FilterState): FileNode {
  return filterNode(root, filters)
}

function filterNode(node: FileNode, filters: FilterState): FileNode {
  if (!node.is_dir) {
    // For files, check if it matches all filters
    const matchesSize = matchesSizeFilter(node.size, filters.size)
    const matchesType = matchesTypeFilter(node.extension, filters.types)
    // Age filter would require mtime field - skip for now

    if (matchesSize && matchesType) {
      return { ...node }
    }
    // Return null-like node with 0 size to indicate filtered out
    return { ...node, size: 0, children: [], file_count: 0 }
  }

  // For directories, recursively filter children
  const filteredChildren = node.children
    .map(child => filterNode(child, filters))
    .filter(child => child.size > 0 || child.is_dir)

  // Recalculate size from filtered children
  const filteredSize = filteredChildren.reduce((sum, child) => sum + child.size, 0)
  const filteredFileCount = filteredChildren.reduce((sum, child) =>
    sum + (child.is_dir ? child.file_count : (child.size > 0 ? 1 : 0)), 0)

  // Only include directory if it has content after filtering
  if (filteredSize === 0 && filteredChildren.length === 0) {
    return { ...node, size: 0, children: [], file_count: 0 }
  }

  return {
    ...node,
    size: filteredSize,
    file_count: filteredFileCount,
    children: filteredChildren.filter(c => c.size > 0 || (c.is_dir && c.children.length > 0)),
  }
}

/**
 * Count total files and size in a tree
 */
export function countFilesAndSize(node: FileNode): { files: number; size: number } {
  if (!node.is_dir) {
    return { files: node.size > 0 ? 1 : 0, size: node.size }
  }

  return node.children.reduce(
    (acc, child) => {
      const childCounts = countFilesAndSize(child)
      return {
        files: acc.files + childCounts.files,
        size: acc.size + childCounts.size,
      }
    },
    { files: 0, size: 0 }
  )
}

/**
 * Check if any filters are active
 */
export function hasActiveFilters(filters: FilterState): boolean {
  return filters.size !== 'all' || filters.types.length > 0 || filters.age !== 'all'
}

/**
 * Count number of active filters
 */
export function countActiveFilters(filters: FilterState): number {
  let count = 0
  if (filters.size !== 'all') count++
  if (filters.types.length > 0) count++
  if (filters.age !== 'all') count++
  return count
}
