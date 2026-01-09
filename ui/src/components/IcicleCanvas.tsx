import { useRef, useEffect, useMemo, useCallback, useState } from 'react'
import { hierarchy as d3Hierarchy, partition as d3Partition, HierarchyRectangularNode } from 'd3-hierarchy'
import { FileNode, getFileCategory, categoryColors, directoryColor, formatSize } from '../types'

interface IcicleCanvasProps {
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

export function IcicleCanvas({ data, width, height, selectedNode, onSelect, onDrillDown }: IcicleCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [tooltip, setTooltip] = useState<TooltipState>({ visible: false, x: 0, y: 0, node: null })
  const [hoveredNode, setHoveredNode] = useState<FileNode | null>(null)

  // Build partition layout
  const root = useMemo(() => {
    const h = d3Hierarchy(data)
      .sum(d => d.is_dir ? 0 : d.size)
      .sort((a, b) => (b.value || 0) - (a.value || 0))

    const p = d3Partition<FileNode>()
      .size([width, height])
      .padding(1)

    return p(h)
  }, [data, width, height])

  // Flatten nodes for hit testing
  const nodes = useMemo(() => root.descendants(), [root])

  // Get color for a node
  const getColor = useCallback((node: FileNode): string => {
    if (node.is_dir) return directoryColor
    const category = getFileCategory(node.extension)
    return categoryColors[category]
  }, [])

  // Find node at position
  const findNodeAtPosition = useCallback((x: number, y: number): HierarchyRectangularNode<FileNode> | null => {
    for (let i = nodes.length - 1; i >= 0; i--) {
      const node = nodes[i]
      if (x >= node.x0 && x <= node.x1 && y >= node.y0 && y <= node.y1) {
        return node
      }
    }
    return null
  }, [nodes])

  // Draw the icicle
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

    // Draw nodes
    for (const node of nodes) {
      const w = node.x1 - node.x0
      const h = node.y1 - node.y0
      if (w < 1 || h < 1) continue

      const isHovered = hoveredNode?.id === node.data.id
      const isSelected = selectedNode?.id === node.data.id

      // Fill
      ctx.fillStyle = getColor(node.data)
      ctx.globalAlpha = isHovered || isSelected ? 1 : 0.85
      ctx.fillRect(node.x0, node.y0, w, h)

      // Stroke
      if (isSelected) {
        ctx.strokeStyle = '#ffffff'
        ctx.lineWidth = 2
      } else if (isHovered) {
        ctx.strokeStyle = '#ffffff'
        ctx.lineWidth = 1.5
      } else {
        ctx.strokeStyle = 'rgba(0,0,0,0.3)'
        ctx.lineWidth = 0.5
      }
      ctx.strokeRect(node.x0, node.y0, w, h)

      ctx.globalAlpha = 1

      // Labels
      if (w > 40 && h > 15) {
        ctx.fillStyle = '#ffffff'
        ctx.font = '500 11px system-ui, -apple-system, sans-serif'
        const name = node.data.name
        const maxChars = Math.floor(w / 7)
        if (maxChars >= 4) {
          const displayName = name.length > maxChars ? name.slice(0, maxChars - 2) + '...' : name
          ctx.fillText(displayName, node.x0 + 4, node.y0 + h / 2 + 4)
        }
      }

      // Size labels
      if (w > 80 && h > 25) {
        ctx.fillStyle = 'rgba(255,255,255,0.7)'
        ctx.font = '10px system-ui, -apple-system, sans-serif'
        const sizeText = formatSize(node.value || node.data.size)
        const textWidth = ctx.measureText(sizeText).width
        ctx.fillText(sizeText, node.x1 - textWidth - 4, node.y0 + h / 2 + 4)
      }
    }
  }, [nodes, width, height, getColor, hoveredNode, selectedNode])

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

    const node = findNodeAtPosition(x, y)

    if (node) {
      setHoveredNode(node.data)
      setTooltip({
        visible: true,
        x: e.clientX + 10,
        y: e.clientY + 10,
        node: node.data,
      })
    } else {
      setHoveredNode(null)
      setTooltip({ visible: false, x: 0, y: 0, node: null })
    }
  }, [findNodeAtPosition])

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

    const node = findNodeAtPosition(x, y)

    if (node) {
      if (node.data.is_dir && node.data.children.length > 0) {
        onDrillDown(node.data)
      } else {
        onSelect(node.data)
      }
    }
  }, [findNodeAtPosition, onDrillDown, onSelect])

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
