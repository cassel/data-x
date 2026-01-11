import { useState } from 'react'
import { Server, Plus, Edit, Trash2, Globe, Key, Lock, MoreVertical } from 'lucide-react'
import { SSHConnection } from '../types'

interface SSHConnectionListProps {
  connections: SSHConnection[]
  isLoading: boolean
  onConnect: (connection: SSHConnection) => void
  onEdit: (connection: SSHConnection) => void
  onDelete: (connection: SSHConnection) => void
  onAddNew: () => void
}

export function SSHConnectionList({
  connections,
  isLoading,
  onConnect,
  onEdit,
  onDelete,
  onAddNew,
}: SSHConnectionListProps) {
  const [menuOpen, setMenuOpen] = useState<string | null>(null)

  const getAuthIcon = (connection: SSHConnection) => {
    switch (connection.auth_method.type) {
      case 'key':
        return <Key className="w-3 h-3 text-green-500" />
      case 'password':
        return <Lock className="w-3 h-3 text-yellow-500" />
      case 'agent':
        return <Server className="w-3 h-3 text-blue-500" />
    }
  }

  const formatLastUsed = (timestamp: number | null) => {
    if (!timestamp) return 'Never used'
    const date = new Date(timestamp * 1000)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))

    if (diffDays === 0) {
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
      if (diffHours === 0) {
        const diffMins = Math.floor(diffMs / (1000 * 60))
        return diffMins <= 1 ? 'Just now' : `${diffMins}m ago`
      }
      return `${diffHours}h ago`
    } else if (diffDays === 1) {
      return 'Yesterday'
    } else if (diffDays < 7) {
      return `${diffDays}d ago`
    } else {
      return date.toLocaleDateString()
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-dark-accent">
        <div className="flex items-center gap-2">
          <Globe className="w-4 h-4 text-accent" />
          <span className="text-sm font-medium">Remote Servers</span>
        </div>
        <button
          onClick={onAddNew}
          className="p-1 rounded hover:bg-dark-accent transition-colors"
          title="Add Connection"
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>

      {/* Connection List */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <div className="animate-spin w-6 h-6 border-2 border-accent border-t-transparent rounded-full" />
          </div>
        ) : connections.length === 0 ? (
          <div className="text-center py-8 px-4">
            <Server className="w-10 h-10 text-gray-600 mx-auto mb-2" />
            <p className="text-sm text-gray-500 mb-3">No connections yet</p>
            <button
              onClick={onAddNew}
              className="text-xs text-accent hover:text-accent-light transition-colors"
            >
              Add your first server
            </button>
          </div>
        ) : (
          <ul className="py-1">
            {connections.map((connection) => (
              <li key={connection.id} className="relative">
                <div
                  onClick={() => onConnect(connection)}
                  className="w-full px-3 py-2 flex items-start gap-3 hover:bg-dark-accent/50 transition-colors text-left group cursor-pointer"
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => e.key === 'Enter' && onConnect(connection)}
                >
                  <div className="flex-shrink-0 w-8 h-8 rounded-lg bg-accent/20 flex items-center justify-center">
                    <Server className="w-4 h-4 text-accent" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium truncate">
                        {connection.name}
                      </span>
                      {getAuthIcon(connection)}
                    </div>
                    <p className="text-xs text-gray-500 truncate">
                      {connection.username}@{connection.host}
                      {connection.port !== 22 ? `:${connection.port}` : ''}
                    </p>
                    <p className="text-xs text-gray-600">
                      {formatLastUsed(connection.last_used_at)}
                    </p>
                  </div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation()
                      setMenuOpen(menuOpen === connection.id ? null : connection.id)
                    }}
                    className="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-dark-accent transition-all"
                  >
                    <MoreVertical className="w-4 h-4 text-gray-400" />
                  </button>
                </div>

                {/* Context Menu */}
                {menuOpen === connection.id && (
                  <>
                    <div
                      className="fixed inset-0 z-40"
                      onClick={() => setMenuOpen(null)}
                    />
                    <div className="absolute right-2 top-10 z-50 bg-dark-panel border border-dark-accent rounded-md shadow-lg py-1 min-w-32">
                      <button
                        onClick={() => {
                          setMenuOpen(null)
                          onEdit(connection)
                        }}
                        className="w-full px-3 py-1.5 text-left text-sm hover:bg-dark-accent flex items-center gap-2"
                      >
                        <Edit className="w-3 h-3" />
                        Edit
                      </button>
                      <button
                        onClick={() => {
                          setMenuOpen(null)
                          onDelete(connection)
                        }}
                        className="w-full px-3 py-1.5 text-left text-sm hover:bg-dark-accent flex items-center gap-2 text-red-400 hover:text-red-300"
                      >
                        <Trash2 className="w-3 h-3" />
                        Delete
                      </button>
                    </div>
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
