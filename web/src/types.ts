export type Snapshot = {
  collectedAt: string
  hostname: string
  cpu: { usagePercent: number; cores: number }
  memory: { usedPct: number; usedBytes: number; totalBytes: number }
  temperatures: Array<{ name: string; celsius: number }>
  battery?: { percent: number; charging: boolean; source: string }
  docker: Array<{ name: string; status: string; healthy: boolean }>
}

export type Device = {
  id: string
  name: string
  online: boolean
  alertState: string
  snapshot?: Snapshot
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

export type Layout = {
  id: string
  deviceId: string
  target: string
  widgets: Widget[]
  updatedAt: string
}

export type EventRecord = {
  id: string
  deviceId: string
  title: string
  body: string
  severity: string
  type: string
  createdAt: string
  resolvedAt?: string
  acknowledgedAt?: string
  acknowledgedBy?: string
}

export type Bootstrap = {
  devices: Device[]
  device?: Device
  layout?: Layout
  alertSummary: {
    activeCount: number
    highestLevel: string
    latestMessage?: string
  }
  events: EventRecord[]
}
