import { FileNode } from '../types'

export interface SearchResult {
  node: FileNode
  parentPath: string
  matchStart: number
  matchEnd: number
}

/**
 * Search for files by name in the file tree
 * Returns up to maxResults matching files
 */
export function searchFiles(
  root: FileNode,
  query: string,
  maxResults: number = 50
): SearchResult[] {
  if (!query || query.length < 2) return []

  const results: SearchResult[] = []
  const lowerQuery = query.toLowerCase()

  function traverse(node: FileNode, parentPath: string) {
    if (results.length >= maxResults) return

    const lowerName = node.name.toLowerCase()
    const matchIndex = lowerName.indexOf(lowerQuery)

    if (matchIndex !== -1) {
      results.push({
        node,
        parentPath,
        matchStart: matchIndex,
        matchEnd: matchIndex + query.length,
      })
    }

    // Continue searching in children
    if (node.is_dir && node.children) {
      const newParentPath = parentPath ? `${parentPath}/${node.name}` : node.name
      for (const child of node.children) {
        if (results.length >= maxResults) break
        traverse(child, newParentPath)
      }
    }
  }

  traverse(root, '')
  return results
}

/**
 * Build a search index for faster searching
 * Returns a flat array of all files with their paths
 */
export function buildSearchIndex(root: FileNode): Array<{ node: FileNode; parentPath: string }> {
  const index: Array<{ node: FileNode; parentPath: string }> = []

  function traverse(node: FileNode, parentPath: string) {
    index.push({ node, parentPath })

    if (node.is_dir && node.children) {
      const newParentPath = parentPath ? `${parentPath}/${node.name}` : node.name
      for (const child of node.children) {
        traverse(child, newParentPath)
      }
    }
  }

  traverse(root, '')
  return index
}

/**
 * Search using a pre-built index (faster for repeated searches)
 */
export function searchWithIndex(
  index: Array<{ node: FileNode; parentPath: string }>,
  query: string,
  maxResults: number = 50
): SearchResult[] {
  if (!query || query.length < 2) return []

  const results: SearchResult[] = []
  const lowerQuery = query.toLowerCase()

  for (const item of index) {
    if (results.length >= maxResults) break

    const lowerName = item.node.name.toLowerCase()
    const matchIndex = lowerName.indexOf(lowerQuery)

    if (matchIndex !== -1) {
      results.push({
        node: item.node,
        parentPath: item.parentPath,
        matchStart: matchIndex,
        matchEnd: matchIndex + query.length,
      })
    }
  }

  return results
}

/**
 * Highlight search term in text
 * Returns an array of segments with isMatch flag
 */
export function highlightMatch(
  text: string,
  matchStart: number,
  matchEnd: number
): Array<{ text: string; isMatch: boolean }> {
  if (matchStart < 0 || matchEnd > text.length) {
    return [{ text, isMatch: false }]
  }

  return [
    { text: text.slice(0, matchStart), isMatch: false },
    { text: text.slice(matchStart, matchEnd), isMatch: true },
    { text: text.slice(matchEnd), isMatch: false },
  ].filter(segment => segment.text.length > 0)
}
