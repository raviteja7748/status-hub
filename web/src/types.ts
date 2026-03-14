export type Snapshot = {
  collectedAt: string
  hostname: string
  uptimeSec: number
  cpu: {
    usagePercent: number
    cores: number
  }
  memory: {
    usedBytes: number
    totalBytes: number
    usedPct: number
  }
  storage: Array<{
    path: string
    usedBytes: number
    totalBytes: number
    usedPct: number
  }>
  network: Array<{
    name: string
    rxBytes: number
    txBytes: number
  }>
  temperatures: Array<{
    name: string
    celsius: number
  }>
  battery?: {
    percent: number
    charging: boolean
    source: string
  }
  docker: Array<{
    name: string
    image: string
    state: string
    status: string
    healthy: boolean
    restartCount: number
  }>
}

export type Device = {
  id: string
  name: string
  lastSeen: string
  online: boolean
  capabilities: Record<string, boolean>
  snapshot?: Snapshot
  alertState: string
}

export type Widget = {
  id: string
  kind: string
  deviceId: string
  title: string
  visible: boolean
  order: number
  size: string
  settings: Record<string, unknown>
}

export type AlertRule = {
  id: string
  deviceId: string
  title: string
  metric: string
  condition: string
  threshold: number
  duration: number
  severity: string
  channels: string[]
  enabled: boolean
  resolveBehavior: string
}

export type EventRecord = {
  id: string
  deviceId: string
  alertRuleId?: string
  type: string
  severity: string
  title: string
  body: string
  createdAt: string
  resolvedAt?: string
}

export type NotificationChannel = {
  id: string
  kind: string
  name: string
  enabled: boolean
  config: Record<string, unknown>
}

