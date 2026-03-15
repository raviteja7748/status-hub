import type { Bootstrap, Device, Widget } from '../types'
import { Thermometer, Battery, Layout, Container } from 'lucide-react'

interface WidgetListProps {
  bootstrap?: Bootstrap
  activeDevice?: Device
}

function widgetValue(widget: Widget, device?: Device) {
  const snapshot = device?.snapshot
  switch (widget.kind) {
    case 'overview':
      return device?.online ? 'Online now' : 'Offline or stale'
    case 'temperature':
      return snapshot?.temperatures[0]
        ? `${snapshot.temperatures[0].celsius.toFixed(1)} C`
        : 'No sensor'
    case 'battery':
      return snapshot?.battery
        ? `${snapshot.battery.percent.toFixed(0)}% ${snapshot.battery.charging ? 'charging' : ''}`
        : 'No battery'
    case 'docker':
      return snapshot?.docker[0]
        ? `${snapshot.docker.filter((container) => container.healthy).length}/${snapshot.docker.length} healthy`
        : 'No containers'
    default:
      return 'Live'
  }
}

function WidgetIcon({ kind }: { kind: string }) {
  switch (kind) {
    case 'temperature': return <Thermometer size={18} />
    case 'battery': return <Battery size={18} />
    case 'docker': return <Container size={18} />
    default: return <Layout size={18} />
  }
}

export function WidgetList({ bootstrap, activeDevice }: WidgetListProps) {
  const widgets = (bootstrap?.layout?.widgets ?? []).filter((widget) => widget.visible)

  return (
    <article className="card panel">
      <div className="panel-head">
        <div>
          <p className="eyebrow">Widgets</p>
          <h2>Mobile layout</h2>
        </div>
      </div>
      <div className="widget-list">
        {widgets.map((widget) => (
          <div key={widget.id} className="widget-row single">
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <div className="widget-icon">
                <WidgetIcon kind={widget.kind} />
              </div>
              <div>
                <strong>{widget.title}</strong>
                <p>{widgetValue(widget, activeDevice)}</p>
              </div>
            </div>
          </div>
        ))}
        {widgets.length === 0 && <p className="empty-state">No widgets configured</p>}
      </div>
    </article>
  )
}
