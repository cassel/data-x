import { useState, useEffect, useCallback } from 'react'
import { invoke } from '@tauri-apps/api/core'
import { SSHConnection, SSHConnectionInput, SSHTestResult } from '../types'

export function useSSHConnections() {
  const [connections, setConnections] = useState<SSHConnection[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Load all connections
  const loadConnections = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      const result = await invoke<SSHConnection[]>('get_ssh_connections')
      setConnections(result)
    } catch (e) {
      setError(String(e))
    } finally {
      setIsLoading(false)
    }
  }, [])

  // Load on mount
  useEffect(() => {
    loadConnections()
  }, [loadConnections])

  // Save a new connection
  const saveConnection = useCallback(async (input: SSHConnectionInput): Promise<SSHConnection> => {
    const result = await invoke<SSHConnection>('save_ssh_connection', { connection: input })
    await loadConnections()
    return result
  }, [loadConnections])

  // Update an existing connection
  const updateConnection = useCallback(async (input: SSHConnectionInput): Promise<SSHConnection> => {
    const result = await invoke<SSHConnection>('update_ssh_connection', { connection: input })
    await loadConnections()
    return result
  }, [loadConnections])

  // Delete a connection
  const deleteConnection = useCallback(async (id: string): Promise<void> => {
    await invoke('delete_ssh_connection', { id })
    await loadConnections()
  }, [loadConnections])

  // Test a connection
  const testConnection = useCallback(async (input: SSHConnectionInput): Promise<SSHTestResult> => {
    return await invoke<SSHTestResult>('test_ssh_connection', { connection: input })
  }, [])

  return {
    connections,
    isLoading,
    error,
    loadConnections,
    saveConnection,
    updateConnection,
    deleteConnection,
    testConnection,
  }
}
