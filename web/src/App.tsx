import { startTransition, useEffect, useEffectEvent, useState } from 'react'
import { api, login } from './api'
import type { AlertRule, Device, EventRecord, NotificationChannel, Widget } from './types'
import './App.css'

const widgetCatalog = [
  { kind: 'overview', title: 'Overview', size: 'wide' },
  { kind: 'cpu-memory', title: 'CPU + Memory', size: 'medium' },
  { kind: 'storage', title: 'Storage', size: 'medium' },
  { kind: 'network', title: 'Network', size: 'medium' },
  { kind: 'temperature', title: 'Temperature', size: 'small' },
  { kind: 'battery', title: 'Battery + Power', size: 'small' },
  { kind: 'docker', title: 'Docker', size: 'wide' },
]

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

const defaultBaseUrl = resolveDefaultBaseUrl()
const defaultToken = localStorage.getItem('status.token') ?? ''

function App() {
  const [baseUrl, setBaseUrl] = useState(defaultBaseUrl)
  const [password, setPassword] = useState('')
  const [token, setToken] = useState(defaultToken)
  const [devices, setDevices] = useState<Device[]>([])
  const [selectedDeviceId, setSelectedDeviceId] = useState('')
  const [widgets, setWidgets] = useState<Widget[]>([])
  const [rules, setRules] = useState<AlertRule[]>([])
  const [events, setEvents] = useState<EventRecord[]>([])
  const [channels, setChannels] = useState<NotificationChannel[]>([])
  const [error, setError] = useState('')
  const [saving, setSaving] = useState('')

  const selectedDevice = devices.find((device) => device.id === selectedDeviceId) ?? devices[0]

  const loadAll = useEffectEvent(async (nextToken: string, nextBaseUrl: string, deviceId?: string) => {
    const nextDevices = await api.devices(nextBaseUrl, nextToken)
    const activeDeviceId = deviceId || nextDevices[0]?.id || ''
    const [nextWidgets, nextRules, nextEvents, nextChannels] = activeDeviceId
      ? await Promise.all([
          api.widgets(nextBaseUrl, nextToken, activeDeviceId),
          api.alerts(nextBaseUrl, nextToken, activeDeviceId),
          api.events(nextBaseUrl, nextToken, activeDeviceId),
          api.channels(nextBaseUrl, nextToken),
        ])
      : [[], [], [], await api.channels(nextBaseUrl, nextToken)]

    startTransition(() => {
      setDevices(nextDevices)
      setSelectedDeviceId(activeDeviceId)
      setWidgets(nextWidgets)
      setRules(nextRules)
      setEvents(nextEvents)
      setChannels(nextChannels)
    })
  })

  useEffect(() => {
    if (!token) {
      return
    }

    loadAll(token, baseUrl).catch((cause: Error) => {
      setError(cause.message)
      setToken('')
      localStorage.removeItem('status.token')
    })
  }, [token, baseUrl, loadAll])

  useEffect(() => {
    if (!token) {
      return
    }

    const wsUrl = baseUrl.replace(/^http/, 'ws') + `/ws/stream?token=${token}`
    const socket = new WebSocket(wsUrl)
    socket.onmessage = (event) => {
      const message = JSON.parse(event.data) as { type: string; device?: Device; event?: EventRecord }
      startTransition(() => {
        if (message.device) {
          setDevices((current) => {
            const next = current.filter((device) => device.id !== message.device?.id)
            return [...next, message.device!].sort((left, right) => left.name.localeCompare(right.name))
          })
        }
        if (message.event) {
          setEvents((current) => [message.event!, ...current].slice(0, 100))
        }
      })
    }
    return () => socket.close()
  }, [baseUrl, token])

  useEffect(() => {
    if (!token || !selectedDeviceId) {
      return
    }
    loadAll(token, baseUrl, selectedDeviceId).catch((cause: Error) => setError(cause.message))
  }, [selectedDeviceId, token, baseUrl, loadAll])

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

  async function saveWidgets() {
    if (!selectedDevice) {
      return
    }
    setSaving('widgets')
    await api.saveWidgets(baseUrl, token, selectedDevice.id, widgets)
    setSaving('')
  }

  async function saveRules() {
    if (!selectedDevice) {
      return
    }
    setSaving('alerts')
    await api.saveAlerts(baseUrl, token, selectedDevice.id, rules)
    setSaving('')
  }

  async function saveChannels() {
    setSaving('channels')
    await api.saveChannels(baseUrl, token, channels)
    setSaving('')
  }

  function moveWidget(index: number, direction: -1 | 1) {
    const target = index + direction
    if (target < 0 || target >= widgets.length) {
      return
    }
    const next = [...widgets]
    ;[next[index], next[target]] = [next[target], next[index]]
    setWidgets(next.map((widget, order) => ({ ...widget, order })))
  }

  function addWidget(kind: string) {
    const entry = widgetCatalog.find((item) => item.kind === kind)
    if (!entry || !selectedDevice) {
      return
    }
    setWidgets((current) => [
      ...current,
      {
        id: crypto.randomUUID(),
        kind: entry.kind,
        deviceId: selectedDevice.id,
        title: entry.title,
        visible: true,
        order: current.length,
        size: entry.size,
        settings: {},
      },
    ])
  }

  if (!token) {
    return (
      <main className="shell auth-shell">
        <section className="auth-card">
          <p className="eyebrow">Status Hub</p>
          <h1>Your Linux laptop, live everywhere</h1>
          <p className="lede">
            Sign in to the self-hosted hub to monitor charging, heat, Docker,
            storage, and alert rules from the Mac menu bar or your phone.
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

  const availableWidgets = widgetCatalog.filter(
    (entry) => !widgets.some((widget) => widget.kind === entry.kind),
  )

  return (
    <main className="shell">
      <section className="hero-panel">
        <div>
          <p className="eyebrow">Status Hub</p>
          <h1>Always-on Linux status, built for menu bar + mobile</h1>
          <p className="lede">
            Live device health, editable widgets, phone-friendly controls, and
            customizable alerts without any AI services.
          </p>
        </div>
        <div className="hero-side">
          <label>
            Device
            <select
              value={selectedDevice?.id ?? ''}
              onChange={(event) => setSelectedDeviceId(event.target.value)}
            >
              {devices.map((device) => (
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

      {selectedDevice ? (
        <section className="overview-grid">
          <article className={`card status-card ${selectedDevice.alertState}`}>
            <h2>{selectedDevice.name}</h2>
            <p>{selectedDevice.online ? 'Online now' : 'Offline or stale'}</p>
            <strong>{selectedDevice.snapshot?.hostname ?? 'Waiting for collector'}</strong>
          </article>
          <article className="card stat-card">
            <span>CPU</span>
            <strong>{selectedDevice.snapshot?.cpu.usagePercent.toFixed(1) ?? '--'}%</strong>
          </article>
          <article className="card stat-card">
            <span>Memory</span>
            <strong>{selectedDevice.snapshot?.memory.usedPct.toFixed(1) ?? '--'}%</strong>
          </article>
          <article className="card stat-card">
            <span>Battery</span>
            <strong>
              {selectedDevice.snapshot?.battery
                ? `${selectedDevice.snapshot.battery.percent.toFixed(0)}%`
                : 'N/A'}
            </strong>
          </article>
        </section>
      ) : null}

      <section className="content-grid">
        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Widgets</p>
              <h2>Dashboard layout</h2>
            </div>
            <button onClick={() => void saveWidgets()}>
              {saving === 'widgets' ? 'Saving...' : 'Save widgets'}
            </button>
          </div>
          <div className="widget-list">
            {widgets.map((widget, index) => (
              <div key={widget.id} className="widget-row">
                <div>
                  <strong>{widget.title}</strong>
                  <p>{widget.kind}</p>
                </div>
                <div className="widget-actions">
                  <label className="toggle">
                    <input
                      type="checkbox"
                      checked={widget.visible}
                      onChange={(event) =>
                        setWidgets((current) =>
                          current.map((entry) =>
                            entry.id === widget.id
                              ? { ...entry, visible: event.target.checked }
                              : entry,
                          ),
                        )
                      }
                    />
                    Visible
                  </label>
                  <button className="secondary" onClick={() => moveWidget(index, -1)}>
                    Up
                  </button>
                  <button className="secondary" onClick={() => moveWidget(index, 1)}>
                    Down
                  </button>
                  <button
                    className="secondary"
                    onClick={() => setWidgets((current) => current.filter((entry) => entry.id !== widget.id))}
                  >
                    Remove
                  </button>
                </div>
              </div>
            ))}
          </div>
          <div className="catalog">
            {availableWidgets.map((widget) => (
              <button key={widget.kind} className="secondary" onClick={() => addWidget(widget.kind)}>
                Add {widget.title}
              </button>
            ))}
          </div>
        </article>

        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Alerts</p>
              <h2>Thresholds and severity</h2>
            </div>
            <button onClick={() => void saveRules()}>
              {saving === 'alerts' ? 'Saving...' : 'Save alerts'}
            </button>
          </div>
          <div className="rule-list">
            {rules.map((rule) => (
              <div key={rule.id} className="rule-row">
                <div className="rule-title">
                  <strong>{rule.title}</strong>
                  <span>{rule.metric}</span>
                </div>
                <label>
                  <input
                    type="checkbox"
                    checked={rule.enabled}
                    onChange={(event) =>
                      setRules((current) =>
                        current.map((entry) =>
                          entry.id === rule.id ? { ...entry, enabled: event.target.checked } : entry,
                        ),
                      )
                    }
                  />
                  Enabled
                </label>
                <label>
                  Threshold
                  <input
                    type="number"
                    value={rule.threshold}
                    onChange={(event) =>
                      setRules((current) =>
                        current.map((entry) =>
                          entry.id === rule.id
                            ? { ...entry, threshold: Number(event.target.value) }
                            : entry,
                        ),
                      )
                    }
                  />
                </label>
                <label>
                  Severity
                  <select
                    value={rule.severity}
                    onChange={(event) =>
                      setRules((current) =>
                        current.map((entry) =>
                          entry.id === rule.id ? { ...entry, severity: event.target.value } : entry,
                        ),
                      )
                    }
                  >
                    <option value="info">Info</option>
                    <option value="warning">Warning</option>
                    <option value="critical">Critical</option>
                  </select>
                </label>
              </div>
            ))}
          </div>
        </article>

        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Delivery</p>
              <h2>Notification channels</h2>
            </div>
            <button onClick={() => void saveChannels()}>
              {saving === 'channels' ? 'Saving...' : 'Save channels'}
            </button>
          </div>
          {channels.map((channel) => (
            <div key={channel.id} className="channel-row">
              <div>
                <strong>{channel.name}</strong>
                <p>{channel.kind}</p>
              </div>
              <label>
                <input
                  type="checkbox"
                  checked={channel.enabled}
                  onChange={(event) =>
                    setChannels((current) =>
                      current.map((entry) =>
                        entry.id === channel.id ? { ...entry, enabled: event.target.checked } : entry,
                      ),
                    )
                  }
                />
                Enabled
              </label>
              <label>
                Server URL
                <input
                  value={String(channel.config.serverURL ?? '')}
                  onChange={(event) =>
                    setChannels((current) =>
                      current.map((entry) =>
                        entry.id === channel.id
                          ? {
                              ...entry,
                              config: { ...entry.config, serverURL: event.target.value },
                            }
                          : entry,
                      ),
                    )
                  }
                />
              </label>
              <label>
                Topic
                <input
                  value={String(channel.config.topic ?? '')}
                  onChange={(event) =>
                    setChannels((current) =>
                      current.map((entry) =>
                        entry.id === channel.id
                          ? {
                              ...entry,
                              config: { ...entry.config, topic: event.target.value },
                            }
                          : entry,
                      ),
                    )
                  }
                />
              </label>
            </div>
          ))}
        </article>

        <article className="card panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Timeline</p>
              <h2>Recent alert history</h2>
            </div>
          </div>
          <div className="event-list">
            {events.map((event) => (
              <div key={event.id} className={`event-row ${event.severity}`}>
                <strong>{event.title}</strong>
                <p>{event.body}</p>
                <span>{new Date(event.createdAt).toLocaleString()}</span>
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
