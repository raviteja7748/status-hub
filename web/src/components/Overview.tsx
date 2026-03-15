import type { AlertSummary, Device } from '../types'
import { Cpu, MemoryStick, Bell, CheckCircle, AlertTriangle, AlertCircle } from 'lucide-react'

interface OverviewProps {
  activeDevice: Device
  alertSummary?: AlertSummary
}

export function Overview({ activeDevice, alertSummary }: OverviewProps) {
  const getAlertIcon = () => {
    switch (activeDevice.alertState) {
      case 'critical': return <AlertCircle size={20} color="var(--red-500, #ef4444)" />
      case 'warning': return <AlertTriangle size={20} color="var(--yellow-500, #f59e0b)" />
      default: return <CheckCircle size={20} color="var(--green-500, #10b981)" />
    }
  }

  return (
    <section className="overview-grid">
      <article className={`card status-card ${activeDevice.alertState}`}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2>{activeDevice.name}</h2>
          {getAlertIcon()}
        </div>
        <p>{activeDevice.online ? 'Online now' : 'Offline or stale'}</p>
        <strong>{alertSummary?.latestMessage ?? 'Healthy'}</strong>
      </article>

      <article className="card stat-card">
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Cpu size={16} />
          <span>CPU</span>
        </div>
        <strong>{activeDevice.snapshot?.cpu.usagePercent.toFixed(1) ?? '--'}%</strong>
      </article>

      <article className="card stat-card">
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <MemoryStick size={16} />
          <span>Memory</span>
        </div>
        <strong>{activeDevice.snapshot?.memory.usedPct.toFixed(1) ?? '--'}%</strong>
      </article>

      <article className="card stat-card">
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Bell size={16} />
          <span>Alerts</span>
        </div>
        <strong>{alertSummary?.activeCount ?? 0}</strong>
      </article>
    </section>
  )
}
