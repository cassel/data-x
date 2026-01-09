import { useRef, useEffect, useMemo, useCallback } from 'react'
import { hierarchy as d3Hierarchy, partition as d3Partition } from 'd3-hierarchy'
import { select } from 'd3-selection'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface IcicleProps {
  data: FileNode
  width: number
  height: number
  selectedNode: FileNode | null
  onSelect: (node: FileNode | null) => void
  onDrillDown: (node: FileNode) => void
}

export function Icicle({ data, width, height, selectedNode, onSelect, onDrillDown }: IcicleProps) {
  const svgRef = useRef<SVGSVGElement>(null)
  const tooltipRef = useRef<HTMLDivElement>(null)

  // Convert FileNode to D3 hierarchy
  const root = useMemo(() => {
    const h = d3Hierarchy(data)
      .sum(d => d.is_dir ? 0 : d.size)
      .sort((a, b) => (b.value || 0) - (a.value || 0))

    const p = d3Partition<FileNode>()
      .size([width, height])
      .padding(1)

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

  // Render icicle
  useEffect(() => {
    if (!svgRef.current) return

    const svg = select(svgRef.current)
    svg.selectAll('*').remove()

    // Create groups for each node
    const nodes = svg
      .selectAll('g')
      .data(root.descendants())
      .join('g')
      .attr('transform', d => `translate(${d.x0},${d.y0})`)

    // Add rectangles
    nodes
      .append('rect')
      .attr('width', d => Math.max(0, d.x1 - d.x0))
      .attr('height', d => Math.max(0, d.y1 - d.y0))
      .attr('fill', d => getColor(d.data))
      .attr('fill-opacity', d => {
        if (selectedNode && d.data.id === selectedNode.id) return 1
        return 0.85
      })
      .attr('stroke', d => {
        if (selectedNode && d.data.id === selectedNode.id) return '#fff'
        return 'rgba(0,0,0,0.3)'
      })
      .attr('stroke-width', d => {
        if (selectedNode && d.data.id === selectedNode.id) return 2
        return 0.5
      })
      .style('cursor', 'pointer')
      .on('click', (event, d) => {
        event.stopPropagation()
        if (d.data.is_dir && d.data.children.length > 0) {
          onDrillDown(d.data)
        } else {
          onSelect(d.data)
        }
      })
      .on('mouseover', (event, d) => {
        select(event.currentTarget)
          .attr('fill-opacity', 1)
          .attr('stroke', '#fff')
          .attr('stroke-width', 1.5)

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
        const isSelected = selectedNode && d.data.id === selectedNode.id
        select(event.currentTarget)
          .attr('fill-opacity', isSelected ? 1 : 0.85)
          .attr('stroke', isSelected ? '#fff' : 'rgba(0,0,0,0.3)')
          .attr('stroke-width', isSelected ? 2 : 0.5)

        if (tooltipRef.current) {
          tooltipRef.current.style.display = 'none'
        }
      })

    // Add labels
    nodes
      .filter(d => (d.x1 - d.x0) > 40 && (d.y1 - d.y0) > 15)
      .append('text')
      .attr('x', 4)
      .attr('y', d => (d.y1 - d.y0) / 2 + 4)
      .attr('fill', '#fff')
      .attr('font-size', '11px')
      .attr('font-weight', '500')
      .style('pointer-events', 'none')
      .text(d => {
        const w = d.x1 - d.x0
        const name = d.data.name
        const maxChars = Math.floor(w / 7)
        if (maxChars < 4) return ''
        if (name.length > maxChars) return name.slice(0, maxChars - 2) + '...'
        return name
      })

    // Add size labels for larger blocks
    nodes
      .filter(d => (d.x1 - d.x0) > 80 && (d.y1 - d.y0) > 25)
      .append('text')
      .attr('x', d => d.x1 - d.x0 - 4)
      .attr('y', d => (d.y1 - d.y0) / 2 + 4)
      .attr('text-anchor', 'end')
      .attr('fill', 'rgba(255,255,255,0.7)')
      .attr('font-size', '10px')
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
