import { useRef, useEffect, useMemo, useCallback } from 'react'
import { scaleLinear } from 'd3-scale'
import { select } from 'd3-selection'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface BarChartProps {
  data: FileNode
  width: number
  height: number
  selectedNode: FileNode | null
  onSelect: (node: FileNode | null) => void
  onDrillDown: (node: FileNode) => void
}

export function BarChart({ data, width, height, selectedNode, onSelect, onDrillDown }: BarChartProps) {
  const svgRef = useRef<SVGSVGElement>(null)
  const tooltipRef = useRef<HTMLDivElement>(null)

  const margin = { top: 20, right: 120, bottom: 20, left: 20 }
  const barHeight = 28
  const barGap = 4
  const maxBars = Math.floor((height - margin.top - margin.bottom) / (barHeight + barGap))

  // Get sorted children by size
  const sortedChildren = useMemo(() => {
    const children = data.children.filter(c => !c.is_hidden)
    return [...children].sort((a, b) => b.size - a.size).slice(0, Math.max(maxBars, 5))
  }, [data, maxBars])

  // Calculate max size for scale
  const maxSize = useMemo(() => {
    return Math.max(...sortedChildren.map(c => c.size), 1)
  }, [sortedChildren])

  // Get color for a node
  const getColor = useCallback((node: FileNode): string => {
    if (node.is_dir) {
      return directoryColor
    }
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }, [])

  // Render bar chart
  useEffect(() => {
    if (!svgRef.current) return

    const svg = select(svgRef.current)
    svg.selectAll('*').remove()

    const chartWidth = width - margin.left - margin.right
    const xScale = scaleLinear()
      .domain([0, maxSize])
      .range([0, chartWidth])

    const g = svg
      .append('g')
      .attr('transform', `translate(${margin.left},${margin.top})`)

    // Create bar groups
    const bars = g
      .selectAll('g')
      .data(sortedChildren)
      .join('g')
      .attr('transform', (_, i) => `translate(0,${i * (barHeight + barGap)})`)

    // Add background bars
    bars
      .append('rect')
      .attr('width', chartWidth)
      .attr('height', barHeight)
      .attr('fill', 'rgba(255,255,255,0.05)')
      .attr('rx', 4)

    // Add colored bars
    bars
      .append('rect')
      .attr('width', d => Math.max(xScale(d.size), 4))
      .attr('height', barHeight)
      .attr('fill', d => getColor(d))
      .attr('fill-opacity', d => {
        if (selectedNode && d.id === selectedNode.id) return 1
        return 0.85
      })
      .attr('stroke', d => {
        if (selectedNode && d.id === selectedNode.id) return '#fff'
        return 'transparent'
      })
      .attr('stroke-width', 2)
      .attr('rx', 4)
      .style('cursor', 'pointer')
      .on('click', (event, d) => {
        event.stopPropagation()
        if (d.is_dir && d.children.length > 0) {
          onDrillDown(d)
        } else {
          onSelect(d)
        }
      })
      .on('mouseover', (event, d) => {
        select(event.currentTarget)
          .attr('fill-opacity', 1)
          .attr('stroke', '#fff')

        if (tooltipRef.current) {
          const tooltip = tooltipRef.current
          tooltip.style.display = 'block'
          tooltip.style.left = `${event.clientX + 10}px`
          tooltip.style.top = `${event.clientY + 10}px`
          tooltip.innerHTML = `
            <div class="font-medium">${d.name}</div>
            <div class="text-sm text-gray-400">${formatSize(d.size)}</div>
            ${d.is_dir ? `<div class="text-xs text-gray-500">${d.file_count} files</div>` : ''}
          `
        }
      })
      .on('mouseout', (event, d) => {
        const isSelected = selectedNode && d.id === selectedNode.id
        select(event.currentTarget)
          .attr('fill-opacity', isSelected ? 1 : 0.85)
          .attr('stroke', isSelected ? '#fff' : 'transparent')

        if (tooltipRef.current) {
          tooltipRef.current.style.display = 'none'
        }
      })

    // Add name labels
    bars
      .append('text')
      .attr('x', 8)
      .attr('y', barHeight / 2 + 4)
      .attr('fill', '#fff')
      .attr('font-size', '12px')
      .attr('font-weight', '500')
      .style('pointer-events', 'none')
      .text(d => {
        const barWidth = xScale(d.size)
        const maxChars = Math.floor(barWidth / 8)
        if (maxChars < 4) return ''
        if (d.name.length > maxChars) return d.name.slice(0, maxChars - 2) + '...'
        return d.name
      })

    // Add size labels on the right
    bars
      .append('text')
      .attr('x', chartWidth + 10)
      .attr('y', barHeight / 2 + 4)
      .attr('fill', '#a0a0a0')
      .attr('font-size', '11px')
      .style('pointer-events', 'none')
      .text(d => formatSize(d.size))

    // Add folder icon for directories
    bars
      .filter(d => d.is_dir)
      .append('text')
      .attr('x', chartWidth + 80)
      .attr('y', barHeight / 2 + 4)
      .attr('fill', '#6b7280')
      .attr('font-size', '10px')
      .style('pointer-events', 'none')
      .text(d => `${d.file_count} files`)

  }, [sortedChildren, maxSize, getColor, selectedNode, onSelect, onDrillDown, width, margin])

  // Calculate actual SVG height based on number of items
  const svgHeight = Math.max(
    margin.top + sortedChildren.length * (barHeight + barGap) + margin.bottom,
    height
  )

  return (
    <div className="relative">
      <svg
        ref={svgRef}
        width={width}
        height={svgHeight}
        viewBox={`0 0 ${width} ${svgHeight}`}
        className="overflow-visible"
      />
      <div
        ref={tooltipRef}
        className="fixed hidden bg-dark-panel border border-dark-accent rounded-lg px-3 py-2 shadow-lg pointer-events-none z-50"
        style={{ maxWidth: '300px' }}
      />
      {sortedChildren.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center text-gray-500">
          No files in this directory
        </div>
      )}
    </div>
  )
}
