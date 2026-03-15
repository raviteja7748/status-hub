import type { Bootstrap, Device, Widget } from '../types'
import { Thermometer, Battery, Layout, Container, Activity, HardDrive, Network } from 'lucide-react'

interface WidgetListProps {
  bootstrap?: Bootstrap
  activeDevice?: Device
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
      return 'Connected'
    case 'network':
      return 'Active'
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
            <div className="widget-tile-content">
              <span className="widget-tile-title">{widget.title}</span>
              <strong className="widget-tile-value">{widgetValue(widget, activeDevice)}</strong>
            </div>
          </div>
        ))}
        {widgets.length === 0 && <p className="empty-state">No widgets configured</p>}
      </div>
    </article>
  )
}
