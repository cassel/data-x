import { useState, useRef, useEffect } from 'react'
import { ChevronDown, Check } from 'lucide-react'

interface FilterOption {
  value: string
  label: string
}

interface FilterDropdownProps {
  label: string
  options: FilterOption[]
  value: string | string[]
  onChange?: (value: string) => void
  onToggle?: (value: string) => void
  multiSelect?: boolean
  icon?: React.ReactNode
}

export function FilterDropdown({
  label,
  options,
  value,
  onChange,
  onToggle,
  multiSelect = false,
  icon,
}: FilterDropdownProps) {
  const [isOpen, setIsOpen] = useState(false)
  const dropdownRef = useRef<HTMLDivElement>(null)

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setIsOpen(false)
      }
    }

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside)
      return () => document.removeEventListener('mousedown', handleClickOutside)
    }
  }, [isOpen])

  const isSelected = (optionValue: string) => {
    if (multiSelect && Array.isArray(value)) {
      return value.includes(optionValue)
    }
    return value === optionValue
  }

  const hasSelection = multiSelect
    ? Array.isArray(value) && value.length > 0
    : value !== 'all'

  const getDisplayValue = () => {
    if (multiSelect && Array.isArray(value) && value.length > 0) {
      if (value.length === 1) {
        const option = options.find(o => o.value === value[0])
        return option?.label || value[0]
      }
      return `${value.length} selected`
    }
    if (!multiSelect && value !== 'all') {
      const option = options.find(o => o.value === value)
      return option?.label || 'All'
    }
    return 'All'
  }

  const handleOptionClick = (optionValue: string) => {
    if (multiSelect && onToggle) {
      onToggle(optionValue)
    } else if (onChange) {
      onChange(optionValue)
      setIsOpen(false)
    }
  }

  return (
    <div ref={dropdownRef} className="relative">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-sm transition-colors ${
          hasSelection
            ? 'bg-accent/20 text-accent border border-accent/30'
            : 'bg-dark-accent/50 text-gray-300 border border-transparent hover:bg-dark-accent'
        }`}
      >
        {icon}
        <span className="text-gray-400 text-xs">{label}:</span>
        <span className="font-medium">{getDisplayValue()}</span>
        <ChevronDown className={`w-4 h-4 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute top-full left-0 mt-1 z-50 min-w-40 bg-dark-panel border border-dark-accent rounded-md shadow-xl py-1">
          {options.map((option) => (
            <button
              key={option.value}
              onClick={() => handleOptionClick(option.value)}
              className={`w-full px-3 py-2 text-left text-sm flex items-center gap-2 hover:bg-dark-accent transition-colors ${
                isSelected(option.value) ? 'text-accent' : 'text-gray-300'
              }`}
            >
              {multiSelect && (
                <div
                  className={`w-4 h-4 rounded border flex items-center justify-center ${
                    isSelected(option.value)
                      ? 'bg-accent border-accent'
                      : 'border-gray-500'
                  }`}
                >
                  {isSelected(option.value) && <Check className="w-3 h-3 text-white" />}
                </div>
              )}
              {!multiSelect && isSelected(option.value) && (
                <Check className="w-4 h-4" />
              )}
              {!multiSelect && !isSelected(option.value) && (
                <div className="w-4" />
              )}
              {option.label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
