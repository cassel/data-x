import { useRef, useEffect, useMemo, useCallback, useState } from 'react'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface BarChartCanvasProps {
  data: FileNode
  width: number
  height: number
  selectedNode: FileNode | null
  onSelect: (node: FileNode | null) => void
  onDrillDown: (node: FileNode) => void
}

interface TooltipState {
  visible: boolean
  x: number
  y: number
  node: FileNode | null
}

interface BarData {
  node: FileNode
  x: number
  y: number
  width: number
  height: number
}

export function BarChartCanvas({ data, width, height, selectedNode, onSelect, onDrillDown }: BarChartCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [tooltip, setTooltip] = useState<TooltipState>({ visible: false, x: 0, y: 0, node: null })
  const [hoveredNode, setHoveredNode] = useState<FileNode | null>(null)

  const margin = { top: 20, right: 120, bottom: 20, left: 20 }
  const barHeight = 28
  const barGap = 4

  // Get sorted children by size
  const sortedChildren = useMemo(() => {
    const maxBars = Math.floor((height - margin.top - margin.bottom) / (barHeight + barGap))
    const children = data.children.filter(c => !c.is_hidden)
    return [...children].sort((a, b) => b.size - a.size).slice(0, Math.max(maxBars, 5))
  }, [data, height, margin.top, margin.bottom])

  // Calculate bar positions
  const bars = useMemo((): BarData[] => {
    const maxSize = Math.max(...sortedChildren.map(c => c.size), 1)
    const chartWidth = width - margin.left - margin.right

    return sortedChildren.map((node, i) => ({
      node,
      x: margin.left,
      y: margin.top + i * (barHeight + barGap),
      width: Math.max((node.size / maxSize) * chartWidth, 4),
      height: barHeight,
    }))
  }, [sortedChildren, width, margin])

  // Get color for a node
  const getColor = useCallback((node: FileNode): string => {
    if (node.is_dir) return directoryColor
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }, [])

  // Find bar at position
  const findBarAtPosition = useCallback((x: number, y: number): BarData | null => {
    for (const bar of bars) {
      if (x >= bar.x && x <= bar.x + bar.width && y >= bar.y && y <= bar.y + bar.height) {
        return bar
      }
    }
    return null
  }, [bars])

  // Draw the chart
  const draw = useCallback(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Scale for retina displays
    const dpr = window.devicePixelRatio || 1
    canvas.width = width * dpr
    canvas.height = height * dpr
    ctx.scale(dpr, dpr)

    // Clear
    ctx.fillStyle = '#1a1a2e'
    ctx.fillRect(0, 0, width, height)

    const chartWidth = width - margin.left - margin.right

    // Draw bars
    for (const bar of bars) {
      const isHovered = hoveredNode?.id === bar.node.id
      const isSelected = selectedNode?.id === bar.node.id

      // Background bar
      ctx.fillStyle = 'rgba(255,255,255,0.05)'
      ctx.beginPath()
      ctx.roundRect(bar.x, bar.y, chartWidth, bar.height, 4)
      ctx.fill()

      // Colored bar
      ctx.fillStyle = getColor(bar.node)
      ctx.globalAlpha = isHovered || isSelected ? 1 : 0.85
      ctx.beginPath()
      ctx.roundRect(bar.x, bar.y, bar.width, bar.height, 4)
      ctx.fill()

      // Stroke for selected/hovered
      if (isSelected || isHovered) {
        ctx.strokeStyle = '#ffffff'
        ctx.lineWidth = 2
        ctx.stroke()
      }

      ctx.globalAlpha = 1

      // Name label
      if (bar.width > 30) {
        ctx.fillStyle = '#ffffff'
        ctx.font = '500 12px system-ui, -apple-system, sans-serif'
        const maxChars = Math.floor(bar.width / 8)
        if (maxChars >= 4) {
          const name = bar.node.name
          const displayName = name.length > maxChars ? name.slice(0, maxChars - 2) + '...' : name
          ctx.fillText(displayName, bar.x + 8, bar.y + bar.height / 2 + 4)
        }
      }

      // Size label on the right
      ctx.fillStyle = '#a0a0a0'
      ctx.font = '11px system-ui, -apple-system, sans-serif'
      ctx.fillText(formatSize(bar.node.size), margin.left + chartWidth + 10, bar.y + bar.height / 2 + 4)

      // File count for directories
      if (bar.node.is_dir) {
        ctx.fillStyle = '#6b7280'
        ctx.font = '10px system-ui, -apple-system, sans-serif'
        ctx.fillText(`${bar.node.file_count} files`, margin.left + chartWidth + 80, bar.y + bar.height / 2 + 4)
      }
    }

    // Empty state
    if (bars.length === 0) {
      ctx.fillStyle = '#6b7280'
      ctx.font = '14px system-ui, -apple-system, sans-serif'
      ctx.textAlign = 'center'
      ctx.fillText('No files in this directory', width / 2, height / 2)
      ctx.textAlign = 'left'
    }
  }, [bars, width, height, margin, getColor, hoveredNode, selectedNode])

  // Redraw when dependencies change
  useEffect(() => {
    draw()
  }, [draw])

  // Handle mouse move
  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current
    if (!canvas) return

    const rect = canvas.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    const bar = findBarAtPosition(x, y)

    if (bar) {
      setHoveredNode(bar.node)
      setTooltip({
        visible: true,
        x: e.clientX + 10,
        y: e.clientY + 10,
        node: bar.node,
      })
    } else {
      setHoveredNode(null)
      setTooltip({ visible: false, x: 0, y: 0, node: null })
    }
  }, [findBarAtPosition])

  // Handle mouse leave
  const handleMouseLeave = useCallback(() => {
    setHoveredNode(null)
    setTooltip({ visible: false, x: 0, y: 0, node: null })
  }, [])

  // Handle click
  const handleClick = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current
    if (!canvas) return

    const rect = canvas.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    const bar = findBarAtPosition(x, y)

    if (bar) {
      if (bar.node.is_dir && bar.node.children.length > 0) {
        onDrillDown(bar.node)
      } else {
        onSelect(bar.node)
      }
    }
  }, [findBarAtPosition, onDrillDown, onSelect])

  return (
    <div className="relative">
      <canvas
        ref={canvasRef}
        width={width}
        height={height}
        style={{ width, height }}
        className="cursor-pointer"
        onMouseMove={handleMouseMove}
        onMouseLeave={handleMouseLeave}
        onClick={handleClick}
      />

      {/* Tooltip */}
      {tooltip.visible && tooltip.node && (
        <div
          className="fixed bg-dark-panel border border-dark-accent rounded-lg px-3 py-2 shadow-lg pointer-events-none z-50"
          style={{ left: tooltip.x, top: tooltip.y, maxWidth: 300 }}
        >
          <div className="font-medium">{tooltip.node.name}</div>
          <div className="text-sm text-gray-400">{formatSize(tooltip.node.size)}</div>
          {tooltip.node.is_dir && (
            <div className="text-xs text-gray-500">{tooltip.node.file_count} files</div>
          )}
        </div>
      )}
    </div>
  )
}
