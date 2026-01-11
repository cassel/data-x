import { useState, useMemo, useCallback } from 'react'
import { FileNode } from '../types'
import {
  FilterState,
  DEFAULT_FILTER_STATE,
  SizeFilter,
  AgeFilter,
  FileType,
  filterFileTree,
  countFilesAndSize,
  hasActiveFilters,
  countActiveFilters,
} from '../utils/filters'

export function useFilters(data: FileNode | null) {
  const [filters, setFilters] = useState<FilterState>(DEFAULT_FILTER_STATE)

  // Filter the data when filters change
  const filteredData = useMemo(() => {
    if (!data) return null
    if (!hasActiveFilters(filters)) return data
    return filterFileTree(data, filters)
  }, [data, filters])

  // Calculate stats for the filtered data
  const stats = useMemo(() => {
    if (!data) return null

    const original = countFilesAndSize(data)
    const filtered = filteredData ? countFilesAndSize(filteredData) : original

    return {
      originalFiles: original.files,
      originalSize: original.size,
      filteredFiles: filtered.files,
      filteredSize: filtered.size,
    }
  }, [data, filteredData])

  // Filter setters
  const setSizeFilter = useCallback((size: SizeFilter) => {
    setFilters(prev => ({ ...prev, size }))
  }, [])

  const setTypeFilter = useCallback((types: FileType[]) => {
    setFilters(prev => ({ ...prev, types }))
  }, [])

  const toggleTypeFilter = useCallback((type: FileType) => {
    setFilters(prev => ({
      ...prev,
      types: prev.types.includes(type)
        ? prev.types.filter(t => t !== type)
        : [...prev.types, type],
    }))
  }, [])

  const setAgeFilter = useCallback((age: AgeFilter) => {
    setFilters(prev => ({ ...prev, age }))
  }, [])

  const clearFilters = useCallback(() => {
    setFilters(DEFAULT_FILTER_STATE)
  }, [])

  return {
    filters,
    filteredData,
    stats,
    isFiltered: hasActiveFilters(filters),
    activeFilterCount: countActiveFilters(filters),
    setSizeFilter,
    setTypeFilter,
    toggleTypeFilter,
    setAgeFilter,
    clearFilters,
  }
}
