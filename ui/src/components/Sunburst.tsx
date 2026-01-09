import { useRef, useEffect, useMemo, useCallback } from 'react'
import { hierarchy as d3Hierarchy, partition as d3Partition } from 'd3-hierarchy'
import { arc as d3Arc } from 'd3-shape'
import { select } from 'd3-selection'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface SunburstProps {
  data: FileNode
  size: number
  selectedNode: FileNode | null
  onSelect: (node: FileNode | null) => void
  onDrillDown: (node: FileNode) => void
}

interface ArcData {
  x0: number
  x1: number
  y0: number
  y1: number
  data: FileNode
}

export function Sunburst({ data, size, selectedNode, onSelect, onDrillDown }: SunburstProps) {
  const svgRef = useRef<SVGSVGElement>(null)
  const tooltipRef = useRef<HTMLDivElement>(null)

  const width = size
  const height = size
  const radius = size / 2

  // Convert FileNode to D3 hierarchy
  const root = useMemo(() => {
    const h = d3Hierarchy(data)
      .sum(d => d.is_dir ? 0 : d.size)
      .sort((a, b) => (b.value || 0) - (a.value || 0))

    const p = d3Partition<FileNode>()
      .size([2 * Math.PI, radius])

    return p(h)
  }, [data, radius])

  // Arc generator
  const arc = useMemo(() =>
    d3Arc<ArcData>()
      .startAngle(d => d.x0)
      .endAngle(d => d.x1)
      .padAngle(0.002)
      .padRadius(radius / 2)
      .innerRadius(d => d.y0)
      .outerRadius(d => d.y1 - 1),
    [radius]
  )

  // Get color for a node
  const getColor = useCallback((node: FileNode): string => {
    if (node.is_dir) {
      return directoryColor
    }
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }, [])

  // Render sunburst
  useEffect(() => {
    if (!svgRef.current) return

    const svg = select(svgRef.current)
    svg.selectAll('*').remove()

    const g = svg
      .append('g')
      .attr('transform', `translate(${width / 2},${height / 2})`)

    // Draw arcs
    g
      .selectAll('path')
      .data(root.descendants().filter(d => d.depth > 0))
      .join('path')
      .attr('fill', d => getColor(d.data))
      .attr('fill-opacity', d => {
        if (selectedNode && d.data.id === selectedNode.id) return 1
        return 0.85
      })
      .attr('d', d => arc({
        x0: d.x0,
        x1: d.x1,
        y0: d.y0,
        y1: d.y1,
        data: d.data,
      }))
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
        // Highlight
        select(event.currentTarget)
          .attr('fill-opacity', 1)
          .attr('stroke', '#fff')
          .attr('stroke-width', 1.5)

        // Show tooltip
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

    // Center circle (go back)
    g.append('circle')
      .attr('r', radius * 0.15)
      .attr('fill', '#1a1a2e')
      .attr('stroke', '#4a90d9')
      .attr('stroke-width', 2)
      .style('cursor', 'pointer')

    // Center text
    g.append('text')
      .attr('text-anchor', 'middle')
      .attr('dy', '-0.5em')
      .attr('fill', '#eaeaea')
      .attr('font-size', '14px')
      .attr('font-weight', 'bold')
      .text(data.name.length > 15 ? data.name.slice(0, 15) + '...' : data.name)

    g.append('text')
      .attr('text-anchor', 'middle')
      .attr('dy', '1em')
      .attr('fill', '#a0a0a0')
      .attr('font-size', '12px')
      .text(formatSize(data.size))

  }, [root, arc, getColor, data, selectedNode, onSelect, onDrillDown, width, height, radius])

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
