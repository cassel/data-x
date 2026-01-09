import { useRef, useEffect, useMemo, useCallback } from 'react'
import { hierarchy as d3Hierarchy, pack as d3Pack } from 'd3-hierarchy'
import { select } from 'd3-selection'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface CirclePackingProps {
  data: FileNode
  size: number
  selectedNode: FileNode | null
  onSelect: (node: FileNode | null) => void
  onDrillDown: (node: FileNode) => void
}

export function CirclePacking({ data, size, selectedNode, onSelect, onDrillDown }: CirclePackingProps) {
  const svgRef = useRef<SVGSVGElement>(null)
  const tooltipRef = useRef<HTMLDivElement>(null)

  const width = size
  const height = size

  // Convert FileNode to D3 hierarchy
  const root = useMemo(() => {
    const h = d3Hierarchy(data)
      .sum(d => d.is_dir ? 0 : d.size)
      .sort((a, b) => (b.value || 0) - (a.value || 0))

    const p = d3Pack<FileNode>()
      .size([width - 4, height - 4])
      .padding(3)

    return p(h)
  }, [data, width, height])

  // Get color for a node
  const getColor = useCallback((node: FileNode): string => {
    if (node.is_dir) {
      return directoryColor
    }
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }, [])

  // Render circle packing
  useEffect(() => {
    if (!svgRef.current) return

    const svg = select(svgRef.current)
    svg.selectAll('*').remove()

    const g = svg
      .append('g')
      .attr('transform', `translate(2,2)`)

    // Draw circles
    g
      .selectAll('circle')
      .data(root.descendants())
      .join('circle')
      .attr('cx', d => d.x)
      .attr('cy', d => d.y)
      .attr('r', d => d.r)
      .attr('fill', d => {
        if (d.depth === 0) return 'transparent'
        if (!d.children) return getColor(d.data)
        return 'transparent'
      })
      .attr('fill-opacity', d => {
        if (d.depth === 0) return 0
        if (selectedNode && d.data.id === selectedNode.id) return 1
        return 0.85
      })
      .attr('stroke', d => {
        if (d.depth === 0) return '#4a90d9'
        if (selectedNode && d.data.id === selectedNode.id) return '#fff'
        if (d.children) return getColor(d.data)
        return 'rgba(0,0,0,0.3)'
      })
      .attr('stroke-width', d => {
        if (d.depth === 0) return 2
        if (selectedNode && d.data.id === selectedNode.id) return 2
        if (d.children) return 1.5
        return 0.5
      })
      .attr('stroke-opacity', d => d.children ? 0.6 : 1)
      .style('cursor', d => d.depth > 0 ? 'pointer' : 'default')
      .on('click', (event, d) => {
        if (d.depth === 0) return
        event.stopPropagation()
        if (d.data.is_dir && d.data.children.length > 0) {
          onDrillDown(d.data)
        } else {
          onSelect(d.data)
        }
      })
      .on('mouseover', (event, d) => {
        if (d.depth === 0) return
        select(event.currentTarget)
          .attr('fill-opacity', d.children ? 0.1 : 1)
          .attr('stroke', '#fff')
          .attr('stroke-width', 2)

        if (tooltipRef.current) {
          const tooltip = tooltipRef.current
          tooltip.style.display = 'block'
          tooltip.style.left = `${event.clientX + 10}px`
          tooltip.style.top = `${event.clientY + 10}px`
          tooltip.innerHTML = `
            <div class="font-medium">${d.data.name}</div>
            <div class="text-sm text-gray-400">${formatSize(d.value || d.data.size)}</div>
            ${d.data.is_dir ? `<div class="text-xs text-gray-500">${d.data.file_count} files</div>` : ''}
          `
        }
      })
      .on('mouseout', (event, d) => {
        if (d.depth === 0) return
        const isSelected = selectedNode && d.data.id === selectedNode.id
        select(event.currentTarget)
          .attr('fill-opacity', () => {
            if (d.children) return 0
            return isSelected ? 1 : 0.85
          })
          .attr('stroke', () => {
            if (isSelected) return '#fff'
            if (d.children) return getColor(d.data)
            return 'rgba(0,0,0,0.3)'
          })
          .attr('stroke-width', () => {
            if (isSelected) return 2
            if (d.children) return 1.5
            return 0.5
          })

        if (tooltipRef.current) {
          tooltipRef.current.style.display = 'none'
        }
      })

    // Add labels for larger circles
    g
      .selectAll('text')
      .data(root.descendants().filter(d => d.r > 25 && d.depth > 0))
      .join('text')
      .attr('x', d => d.x)
      .attr('y', d => d.children ? d.y - d.r + 14 : d.y)
      .attr('text-anchor', 'middle')
      .attr('fill', d => d.children ? 'rgba(255,255,255,0.7)' : '#fff')
      .attr('font-size', d => Math.min(d.r / 3, 12))
      .attr('font-weight', '500')
      .style('pointer-events', 'none')
      .text(d => {
        const maxChars = Math.floor(d.r * 2 / 7)
        if (maxChars < 3) return ''
        if (d.data.name.length > maxChars) return d.data.name.slice(0, maxChars - 2) + '...'
        return d.data.name
      })

    // Add size labels for leaf nodes with enough space
    g
      .selectAll('.size-label')
      .data(root.leaves().filter(d => d.r > 30))
      .join('text')
      .attr('class', 'size-label')
      .attr('x', d => d.x)
      .attr('y', d => d.y + 12)
      .attr('text-anchor', 'middle')
      .attr('fill', 'rgba(255,255,255,0.7)')
      .attr('font-size', d => Math.min(d.r / 4, 10))
      .style('pointer-events', 'none')
      .text(d => formatSize(d.value || d.data.size))

  }, [root, getColor, selectedNode, onSelect, onDrillDown])

  return (
    <div className="relative">
      <svg
        ref={svgRef}
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        className="overflow-visible"
      />
      <div
        ref={tooltipRef}
        className="fixed hidden bg-dark-panel border border-dark-accent rounded-lg px-3 py-2 shadow-lg pointer-events-none z-50"
        style={{ maxWidth: '300px' }}
      />
    </div>
  )
}
