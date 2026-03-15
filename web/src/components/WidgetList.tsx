import type { Bootstrap, Device, Widget } from '../types'
import { Thermometer, Battery, Layout, Container, Activity, HardDrive, Network } from 'lucide-react'

interface WidgetListProps {
  bootstrap?: Bootstrap
  activeDevice?: Device
}

function formatBytes(bytes: number) {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

function widgetValue(widget: Widget, device?: Device) {
  const snapshot = device?.snapshot
  switch (widget.kind) {
    case 'overview':
      return device?.online ? 'Online' : 'Offline'
    case 'temperature':
      return snapshot?.temperatures[0]
        ? `${snapshot.temperatures[0].celsius.toFixed(1)}°C`
        : 'No sensor'
    case 'battery':
      return snapshot?.battery
        ? `${snapshot.battery.percent.toFixed(0)}% ${snapshot.battery.charging ? '(Charging)' : ''}`
        : 'No battery'
    case 'docker':
      return snapshot?.docker && snapshot.docker.length > 0
        ? `${snapshot.docker.filter((container) => container.healthy).length}/${snapshot.docker.length} healthy`
        : 'No containers'
    case 'storage':
      return snapshot?.storage[0]
        ? `${snapshot.storage[0].usedPct.toFixed(0)}% full`
        : 'No storage'
    case 'network':
      const def = snapshot?.network.find(n => n.isDefault)
      return def ? `Up: ${formatBytes(def.txBytes)}` : 'No network'
    default:
      return 'Live'
  }
}

function WidgetIcon({ kind }: { kind: string }) {
  switch (kind) {
    case 'temperature': return <Thermometer size={20} />
    case 'battery': return <Battery size={20} />
    case 'docker': return <Container size={20} />
    case 'overview': return <Activity size={20} />
    case 'storage': return <HardDrive size={20} />
    case 'network': return <Network size={20} />
    default: return <Layout size={20} />
  }
}

export function WidgetList({ bootstrap, activeDevice }: WidgetListProps) {
  const widgets = (bootstrap?.layout?.widgets ?? []).filter((widget) => widget.visible)

  return (
    <article className="card panel">
      <div className="panel-head">
        <div>
          <p className="eyebrow">Status</p>
          <h2>Resource Widgets</h2>
        </div>
      </div>
      <div className="widget-grid">
        {widgets.map((widget) => (
          <div key={widget.id} className={`widget-tile ${widget.kind}`}>
            <div className="widget-tile-icon">
              <WidgetIcon kind={widget.kind} />
            </div>
            <div className="widget-tile-content" style={{ flex: 1 }}>
              <span className="widget-tile-title">{widget.title}</span>
              <strong className="widget-tile-value">{widgetValue(widget, activeDevice)}</strong>
              
              {widget.kind === 'storage' && activeDevice?.snapshot?.storage[0] && (
                <div className="mini-progress-bg" style={{ marginTop: '8px' }}>
                  <div 
                    className="mini-progress-fill" 
                    style={{ 
                      width: `${activeDevice.snapshot.storage[0].usedPct}%`,
                      background: activeDevice.snapshot.storage[0].usedPct > 90 ? '#ef4444' : '#8b5cf6'
                    }} 
                  />
                </div>
              )}
            </div>
          </div>
        ))}
        {widgets.length === 0 && <p className="empty-state">No widgets configured</p>}
      </div>
    </article>
  )
}
