import type { AlertSummary, Device } from '../types'
import { Cpu, MemoryStick, Bell, CheckCircle, AlertTriangle, AlertCircle } from 'lucide-react'

interface OverviewProps {
  activeDevice: Device
  alertSummary?: AlertSummary
}

interface GaugeProps {
  value: number
  label: string
  icon: React.ReactNode
  color?: string
}

function Gauge({ value, label, icon, color = '#3b82f6' }: GaugeProps) {
  const radius = 36
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (value / 100) * circumference

  return (
    <article className="card stat-card gauge-card">
      <div className="gauge-container">
        <svg viewBox="0 0 100 100" className="gauge-svg">
          <circle
            className="gauge-bg"
            cx="50"
            cy="50"
            r={radius}
            strokeWidth="8"
            fill="transparent"
          />
          <circle
            className="gauge-value"
            cx="50"
            cy="50"
            r={radius}
            strokeWidth="8"
            fill="transparent"
            stroke={color}
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            strokeLinecap="round"
            transform="rotate(-90 50 50)"
          />
          <text x="50" y="55" textAnchor="middle" className="gauge-text">
            {value.toFixed(0)}%
          </text>
        </svg>
      </div>
      <div className="gauge-info">
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px', justifyContent: 'center' }}>
          {icon}
          <span>{label}</span>
        </div>
      </div>
    </article>
  )
}

export function Overview({ activeDevice, alertSummary }: OverviewProps) {
  const getAlertIcon = () => {
    switch (activeDevice.alertState) {
      case 'critical': return <AlertCircle size={24} color="#ef4444" />
      case 'warning': return <AlertTriangle size={24} color="#f59e0b" />
      default: return <CheckCircle size={24} color="#10b981" />
    }
  }

  const cpuUsage = activeDevice.snapshot?.cpu.usagePercent ?? 0
  const memUsage = activeDevice.snapshot?.memory.usedPct ?? 0

  return (
    <section className="overview-grid">
      <article className={`card status-card ${activeDevice.alertState}`}>
        <div className="status-header">
          <div>
            <h2>{activeDevice.name}</h2>
            <p className={`online-indicator ${activeDevice.online ? 'online' : 'offline'}`}>
              {activeDevice.online ? 'Online' : 'Offline'}
            </p>
          </div>
          {getAlertIcon()}
        </div>
        <div className="status-message">
          <strong>{alertSummary?.latestMessage ?? 'System Healthy'}</strong>
        </div>
      </article>

      <Gauge 
        value={cpuUsage} 
        label="CPU" 
        icon={<Cpu size={14} />} 
        color={cpuUsage > 80 ? '#ef4444' : cpuUsage > 50 ? '#f59e0b' : '#3b82f6'}
      />

      <Gauge 
        value={memUsage} 
        label="Memory" 
        icon={<MemoryStick size={14} />} 
        color={memUsage > 90 ? '#ef4444' : memUsage > 70 ? '#f59e0b' : '#10b981'}
      />

      <article className="card stat-card alert-count-card">
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
          <Bell size={24} className={alertSummary?.activeCount ? 'pulse-animation' : ''} />
          <strong style={{ fontSize: '1.5rem', marginTop: '8px' }}>{alertSummary?.activeCount ?? 0}</strong>
          <span>Alerts</span>
        </div>
      </article>
    </section>
  )
}
