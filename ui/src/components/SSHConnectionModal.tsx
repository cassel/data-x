import { useState, useEffect } from 'react'
import { X, Key, Lock, Server, CheckCircle, XCircle, Loader2 } from 'lucide-react'
import { SSHConnection, SSHConnectionInput, SSHTestResult, AuthMethod } from '../types'

interface SSHConnectionModalProps {
  isOpen: boolean
  onClose: () => void
  connection?: SSHConnection | null
  onSave: (input: SSHConnectionInput) => Promise<SSHConnection>
  onTest: (input: SSHConnectionInput) => Promise<SSHTestResult>
}

export function SSHConnectionModal({
  isOpen,
  onClose,
  connection,
  onSave,
  onTest,
}: SSHConnectionModalProps) {
  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [port, setPort] = useState(22)
  const [username, setUsername] = useState('')
  const [authType, setAuthType] = useState<'key' | 'password' | 'agent'>('key')
  const [keyPath, setKeyPath] = useState('')
  const [password, setPassword] = useState('')
  const [defaultPath, setDefaultPath] = useState('')
  const [timeoutSecs, setTimeoutSecs] = useState(30)

  const [isTesting, setIsTesting] = useState(false)
  const [testResult, setTestResult] = useState<SSHTestResult | null>(null)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Reset form when modal opens/closes or connection changes
  useEffect(() => {
    if (isOpen) {
      if (connection) {
        setName(connection.name)
        setHost(connection.host)
        setPort(connection.port)
        setUsername(connection.username)
        setAuthType(connection.auth_method.type)
        if (connection.auth_method.type === 'key' && connection.auth_method.key_path) {
          setKeyPath(connection.auth_method.key_path)
        } else {
          setKeyPath('')
        }
        setPassword('')
        setDefaultPath(connection.default_path || '')
        setTimeoutSecs(connection.timeout_secs)
      } else {
        // Reset to defaults for new connection
        setName('')
        setHost('')
        setPort(22)
        setUsername('')
        setAuthType('key')
        setKeyPath('')
        setPassword('')
        setDefaultPath('')
        setTimeoutSecs(30)
      }
      setTestResult(null)
      setError(null)
    }
  }, [isOpen, connection])

  // Handle escape key
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) onClose()
    }
    document.addEventListener('keydown', handleEsc)
    return () => document.removeEventListener('keydown', handleEsc)
  }, [isOpen, onClose])

  if (!isOpen) return null

  const buildAuthMethod = (): AuthMethod => {
    switch (authType) {
      case 'key':
        return { type: 'key', key_path: keyPath || null }
      case 'password':
        return { type: 'password' }
      case 'agent':
        return { type: 'agent' }
    }
  }

  const buildInput = (): SSHConnectionInput => ({
    id: connection?.id,
    name,
    host,
    port,
    username,
    auth_method: buildAuthMethod(),
    password: authType === 'password' ? password : undefined,
    default_path: defaultPath || undefined,
    timeout_secs: timeoutSecs,
  })

  const handleTest = async () => {
    setIsTesting(true)
    setTestResult(null)
    setError(null)
    try {
      const result = await onTest(buildInput())
      setTestResult(result)
    } catch (e) {
      setError(String(e))
    } finally {
      setIsTesting(false)
    }
  }

  const handleSave = async () => {
    setIsSaving(true)
    setError(null)
    try {
      await onSave(buildInput())
      onClose()
    } catch (e) {
      setError(String(e))
    } finally {
      setIsSaving(false)
    }
  }

  const isValid = name.trim() && host.trim() && username.trim()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />
      <div className="relative bg-dark-panel border border-dark-accent rounded-lg shadow-xl max-w-lg w-full mx-4 max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-dark-accent">
          <div className="flex items-center gap-2">
            <Server className="w-5 h-5 text-accent" />
            <h2 className="font-semibold">
              {connection ? 'Edit Connection' : 'New SSH Connection'}
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-1 rounded hover:bg-dark-accent transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Form */}
        <div className="p-4 space-y-4 overflow-y-auto flex-1">
          {/* Connection Name */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">Connection Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="My Server"
              className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
            />
          </div>

          {/* Host and Port */}
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm text-gray-400 mb-1">Host</label>
              <input
                type="text"
                value={host}
                onChange={(e) => setHost(e.target.value)}
                placeholder="192.168.1.100 or server.example.com"
                className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
              />
            </div>
            <div className="w-24">
              <label className="block text-sm text-gray-400 mb-1">Port</label>
              <input
                type="number"
                value={port}
                onChange={(e) => setPort(parseInt(e.target.value) || 22)}
                className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
              />
            </div>
          </div>

          {/* Username */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="root"
              className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
            />
          </div>

          {/* Auth Method */}
          <div>
            <label className="block text-sm text-gray-400 mb-2">Authentication</label>
            <div className="flex gap-2">
              <button
                onClick={() => setAuthType('key')}
                className={`flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-md border transition-colors ${
                  authType === 'key'
                    ? 'bg-accent/20 border-accent text-accent'
                    : 'border-dark-accent hover:border-gray-500'
                }`}
              >
                <Key className="w-4 h-4" />
                SSH Key
              </button>
              <button
                onClick={() => setAuthType('password')}
                className={`flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-md border transition-colors ${
                  authType === 'password'
                    ? 'bg-accent/20 border-accent text-accent'
                    : 'border-dark-accent hover:border-gray-500'
                }`}
              >
                <Lock className="w-4 h-4" />
                Password
              </button>
              <button
                onClick={() => setAuthType('agent')}
                className={`flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-md border transition-colors ${
                  authType === 'agent'
                    ? 'bg-accent/20 border-accent text-accent'
                    : 'border-dark-accent hover:border-gray-500'
                }`}
              >
                <Server className="w-4 h-4" />
                Agent
              </button>
            </div>
          </div>

          {/* Key Path (for SSH Key auth) */}
          {authType === 'key' && (
            <div>
              <label className="block text-sm text-gray-400 mb-1">
                Private Key Path <span className="text-gray-600">(optional)</span>
              </label>
              <input
                type="text"
                value={keyPath}
                onChange={(e) => setKeyPath(e.target.value)}
                placeholder="~/.ssh/id_rsa"
                className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
              />
              <p className="text-xs text-gray-500 mt-1">
                Leave empty to use default SSH key
              </p>
            </div>
          )}

          {/* Password (for password auth) */}
          {authType === 'password' && (
            <div>
              <label className="block text-sm text-gray-400 mb-1">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter password"
                className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
              />
              <p className="text-xs text-yellow-500/80 mt-1">
                Password will be stored securely in your system keychain
              </p>
            </div>
          )}

          {/* Default Path */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">
              Default Path <span className="text-gray-600">(optional)</span>
            </label>
            <input
              type="text"
              value={defaultPath}
              onChange={(e) => setDefaultPath(e.target.value)}
              placeholder="/"
              className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
            />
          </div>

          {/* Timeout */}
          <div>
            <label className="block text-sm text-gray-400 mb-1">
              Connection Timeout (seconds)
            </label>
            <input
              type="number"
              value={timeoutSecs}
              onChange={(e) => setTimeoutSecs(parseInt(e.target.value) || 30)}
              className="w-full px-3 py-2 bg-dark-bg border border-dark-accent rounded-md focus:outline-none focus:border-accent"
            />
          </div>

          {/* Test Result */}
          {testResult && (
            <div
              className={`p-3 rounded-md ${
                testResult.success
                  ? 'bg-green-500/10 border border-green-500/30'
                  : 'bg-red-500/10 border border-red-500/30'
              }`}
            >
              <div className="flex items-center gap-2">
                {testResult.success ? (
                  <CheckCircle className="w-5 h-5 text-green-500" />
                ) : (
                  <XCircle className="w-5 h-5 text-red-500" />
                )}
                <span className={testResult.success ? 'text-green-400' : 'text-red-400'}>
                  {testResult.message}
                </span>
              </div>
              {testResult.server_info && (
                <p className="text-xs text-gray-400 mt-1 ml-7">
                  {testResult.server_info}
                </p>
              )}
              {testResult.latency_ms && (
                <p className="text-xs text-gray-500 mt-1 ml-7">
                  Latency: {testResult.latency_ms}ms
                </p>
              )}
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="p-3 rounded-md bg-red-500/10 border border-red-500/30">
              <p className="text-red-400 text-sm">{error}</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-4 py-3 border-t border-dark-accent bg-dark-bg/50">
          <button
            onClick={handleTest}
            disabled={!isValid || isTesting}
            className="flex items-center gap-2 px-4 py-2 rounded-md border border-dark-accent hover:border-accent disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {isTesting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Server className="w-4 h-4" />
            )}
            Test Connection
          </button>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 rounded-md border border-dark-accent hover:bg-dark-accent transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={!isValid || isSaving}
              className="flex items-center gap-2 px-4 py-2 rounded-md bg-accent hover:bg-accent-light disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {isSaving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : null}
              {connection ? 'Save Changes' : 'Add Connection'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
