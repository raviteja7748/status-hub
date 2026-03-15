import { startTransition, useEffect, useEffectEvent, useState } from 'react'
import { api, login } from './api'
import type { Bootstrap, Device, EventRecord, Widget } from './types'
import './App.css'

function resolveDefaultBaseUrl() {
  const saved = localStorage.getItem('status.baseUrl')
  const currentOrigin = window.location.origin
  if (saved && (!saved.includes('localhost') || currentOrigin.includes('localhost'))) {
    return saved
  }
  if (currentOrigin.startsWith('http')) {
    return currentOrigin
  }
  return 'http://localhost:8080'
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

const defaultBaseUrl = resolveDefaultBaseUrl()

function App() {
  const [baseUrl, setBaseUrl] = useState(defaultBaseUrl)
  const [password, setPassword] = useState('')
  const [token, setToken] = useState(localStorage.getItem('status.token') ?? '')
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null)
  const [selectedDeviceId, setSelectedDeviceId] = useState('')
  const [error, setError] = useState('')
  const [busyEventId, setBusyEventId] = useState('')

  const activeDevice = bootstrap?.devices.find((device) => device.id === selectedDeviceId) ?? bootstrap?.device

  const loadBootstrap = useEffectEvent(async (nextToken: string, nextBaseUrl: string, deviceId?: string) => {
    const next = await api.bootstrap(nextBaseUrl, nextToken, deviceId)
    startTransition(() => {
      setBootstrap(next)
      setSelectedDeviceId(next.device?.id ?? next.devices[0]?.id ?? '')
    })
  })

  useEffect(() => {
    if (!token) {
      return
    }
    loadBootstrap(token, baseUrl).catch((cause: Error) => {
      setError(cause.message)
      setToken('')
      localStorage.removeItem('status.token')
    })
  }, [token, baseUrl, loadBootstrap])

  useEffect(() => {
    if (!token || !selectedDeviceId) {
      return
    }
    const ws = new WebSocket(baseUrl.replace(/^http/, 'ws') + `/ws/stream?token=${token}`)
    ws.onmessage = () => {
      loadBootstrap(token, baseUrl, selectedDeviceId).catch((cause: Error) => setError(cause.message))
    }
    return () => ws.close()
  }, [token, baseUrl, selectedDeviceId, loadBootstrap])

  async function handleLogin(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    try {
      const result = await login(baseUrl, password)
      localStorage.setItem('status.baseUrl', baseUrl)
      localStorage.setItem('status.token', result.token)
      setToken(result.token)
      setError('')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Login failed')
    }
  }

  async function acknowledge(eventItem: EventRecord) {
    setBusyEventId(eventItem.id)
    try {
      await api.acknowledgeEvent(baseUrl, token, eventItem.id)
      await loadBootstrap(token, baseUrl, selectedDeviceId)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Acknowledge failed')
    } finally {
      setBusyEventId('')
    }
  }

  if (!token) {
    return (
      <main className="shell auth-shell">
        <section className="auth-card">
          <p className="eyebrow">Status Hub</p>
          <h1>Phone view for your Linux status</h1>
          <p className="lede">
            This browser view is now the lighter companion. The main editing
            experience is moving to the Mac menu bar app.
          </p>
          <form onSubmit={handleLogin}>
            <label>
              Hub URL
              <input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} />
            </label>
            <label>
              Admin password
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            <button type="submit">Connect</button>
          </form>
          {error ? <p className="error">{error}</p> : null}
        </section>
      </main>
    )
  }

  return (
    <main className="shell">
      <section className="hero-panel">
        <div>
          <p className="eyebrow">Status Hub</p>
          <h1>Mobile companion</h1>
          <p className="lede">
            Quick status, alert history, and light controls while the Mac menu
            bar becomes the main control center.
          </p>
        </div>
        <div className="hero-side">
          <label>
            Device
            <select
              value={selectedDeviceId}
              onChange={(event) => {
                setSelectedDeviceId(event.target.value)
                void loadBootstrap(token, baseUrl, event.target.value)
              }}
            >
              {(bootstrap?.devices ?? []).map((device) => (
                <option key={device.id} value={device.id}>
                  {device.name}
                </option>
              ))}
            </select>
          </label>
          <button
            className="secondary"
            onClick={() => {
              localStorage.removeItem('status.token')
              setToken('')
            }}
          >
            Sign out
          </button>
        </div>
      </section>

      {activeDevice ? (
        <section className="overview-grid">
          <article className={`card status-card ${activeDevice.alertState}`}>
            <h2>{activeDevice.name}</h2>
            <p>{activeDevice.online ? 'Online now' : 'Offline or stale'}</p>
            <strong>{bootstrap?.alertSummary.latestMessage ?? 'Healthy'}</strong>
          </article>
          <article className="card stat-card">
            <span>CPU</span>
            <strong>{activeDevice.snapshot?.cpu.usagePercent.toFixed(1) ?? '--'}%</strong>
          </article>
          <article className="card stat-card">
            <span>Memory</span>
            <strong>{activeDevice.snapshot?.memory.usedPct.toFixed(1) ?? '--'}%</strong>
          </article>
          <article className="card stat-card">
            <span>Alerts</span>
            <strong>{bootstrap?.alertSummary.activeCount ?? 0}</strong>
          </article>
        </section>
      ) : null}

      <section className="content-grid single-column">
        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Widgets</p>
              <h2>Mobile layout</h2>
            </div>
          </div>
          <div className="widget-list">
            {(bootstrap?.layout?.widgets ?? []).filter((widget) => widget.visible).map((widget) => (
              <div key={widget.id} className="widget-row single">
                <div>
                  <strong>{widget.title}</strong>
                  <p>{widgetValue(widget, activeDevice)}</p>
                </div>
              </div>
            ))}
          </div>
        </article>

        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Alerts</p>
              <h2>Recent alert history</h2>
            </div>
          </div>
          <div className="event-list">
            {(bootstrap?.events ?? []).map((eventItem) => (
              <div key={eventItem.id} className={`event-row ${eventItem.severity}`}>
                <strong>{eventItem.title}</strong>
                <p>{eventItem.body}</p>
                <span>{new Date(eventItem.createdAt).toLocaleString()}</span>
                {eventItem.acknowledgedAt ? (
                  <span className="acked">Acknowledged</span>
                ) : (
                  <button
                    className="secondary"
                    onClick={() => void acknowledge(eventItem)}
                    disabled={busyEventId === eventItem.id}
                  >
                    {busyEventId === eventItem.id ? 'Saving...' : 'Acknowledge'}
                  </button>
                )}
              </div>
            ))}
          </div>
        </article>
      </section>
      {error ? <p className="error">{error}</p> : null}
    </main>
  )
}

export default App
