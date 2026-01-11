import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import { FileNode } from '../types'
import { buildSearchIndex, searchWithIndex } from '../utils/search'

const DEBOUNCE_MS = 150
const MAX_RESULTS = 10

export function useSearch(data: FileNode | null) {
  const [query, setQuery] = useState('')
  const [debouncedQuery, setDebouncedQuery] = useState('')
  const [isOpen, setIsOpen] = useState(false)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Build search index when data changes
  const searchIndex = useMemo(() => {
    if (!data) return []
    return buildSearchIndex(data)
  }, [data])

  // Debounce the query
  useEffect(() => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current)
    }

    debounceRef.current = setTimeout(() => {
      setDebouncedQuery(query)
    }, DEBOUNCE_MS)

    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current)
      }
    }
  }, [query])

  // Search results
  const results = useMemo(() => {
    if (!debouncedQuery || debouncedQuery.length < 2) return []
    return searchWithIndex(searchIndex, debouncedQuery, MAX_RESULTS)
  }, [searchIndex, debouncedQuery])

  // Reset selected index when results change
  useEffect(() => {
    setSelectedIndex(0)
  }, [results])

  // Open dropdown when we have results
  useEffect(() => {
    if (results.length > 0 && query.length >= 2) {
      setIsOpen(true)
    }
  }, [results, query])

  // Handle query change
  const handleQueryChange = useCallback((newQuery: string) => {
    setQuery(newQuery)
    if (newQuery.length < 2) {
      setIsOpen(false)
    }
  }, [])

  // Clear search
  const clearSearch = useCallback(() => {
    setQuery('')
    setDebouncedQuery('')
    setIsOpen(false)
    setSelectedIndex(0)
  }, [])

  // Close dropdown
  const closeDropdown = useCallback(() => {
    setIsOpen(false)
  }, [])

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (!isOpen || results.length === 0) return

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        setSelectedIndex(prev => Math.min(prev + 1, results.length - 1))
        break
      case 'ArrowUp':
        e.preventDefault()
        setSelectedIndex(prev => Math.max(prev - 1, 0))
        break
      case 'Enter':
        e.preventDefault()
        if (results[selectedIndex]) {
          return results[selectedIndex]
        }
        break
      case 'Escape':
        e.preventDefault()
        closeDropdown()
        break
    }
    return null
  }, [isOpen, results, selectedIndex, closeDropdown])

  // Get selected result
  const getSelectedResult = useCallback(() => {
    if (selectedIndex >= 0 && selectedIndex < results.length) {
      return results[selectedIndex]
    }
    return null
  }, [results, selectedIndex])

  return {
    query,
    results,
    isOpen,
    selectedIndex,
    isSearching: query !== debouncedQuery,
    hasResults: results.length > 0,
    noResults: query.length >= 2 && debouncedQuery.length >= 2 && results.length === 0,
    handleQueryChange,
    clearSearch,
    closeDropdown,
    handleKeyDown,
    getSelectedResult,
    setSelectedIndex,
    setIsOpen,
  }
}
