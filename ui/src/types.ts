// Type definitions matching Rust backend

export interface FileNode {
  id: number
  name: string
  path: string
  size: number
  is_dir: boolean
  is_hidden: boolean
  extension: string | null
  children: FileNode[]
  file_count: number
}

export interface ScanResult {
  root: FileNode
  total_files: number
  total_size: number
  scan_time_ms: number
}

export interface DiskInfo {
  total: number
  used: number
  available: number
  mount_point: string
}

export type FileCategory =
  | 'audio'
  | 'video'
  | 'image'
  | 'document'
  | 'code'
  | 'archive'
  | 'application'
  | 'system'
  | 'other'

export function getFileCategory(extension: string | null): FileCategory {
  if (!extension) return 'other'

  const ext = extension.toLowerCase()

  if (['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].includes(ext)) return 'audio'
  if (['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'].includes(ext)) return 'video'
  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'heic'].includes(ext)) return 'image'
  if (['pdf', 'doc', 'docx', 'txt', 'rtf', 'xls', 'xlsx', 'ppt'].includes(ext)) return 'document'
  if (['rs', 'py', 'js', 'ts', 'go', 'c', 'cpp', 'java', 'swift', 'html', 'css', 'json'].includes(ext)) return 'code'
  if (['zip', 'tar', 'gz', 'rar', '7z', 'dmg', 'iso'].includes(ext)) return 'archive'
  if (['app', 'exe', 'dll', 'so', 'dylib'].includes(ext)) return 'application'
  if (['sys', 'log', 'plist', 'db'].includes(ext)) return 'system'

  return 'other'
}

export const categoryColors: Record<FileCategory, string> = {
  audio: '#c864dc',      // Purple
  video: '#dc5050',      // Red
  image: '#64c864',      // Green
  document: '#6496dc',   // Blue
  code: '#dcc850',       // Yellow
  archive: '#dc9650',    // Orange
  application: '#b4b4dc', // Light purple
  system: '#969696',     // Gray
  other: '#788ca0',      // Blue-gray
}

export const directoryColor = '#4a90d9'

export function formatSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let size = bytes
  let unitIndex = 0

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex++
  }

  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`
}
