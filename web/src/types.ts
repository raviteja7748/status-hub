export type CPUStats = {
  usagePercent: number
  cores: number
}

export type MemoryStats = {
  usedPct: number
  usedBytes: number
  totalBytes: number
}

export type DiskStats = {
  path: string
  usedBytes: number
  totalBytes: number
  usedPct: number
}

export type NetworkStats = {
  name: string
  rxBytes: number
  txBytes: number
  isDefault: boolean
}

export type TemperatureStat = {
  name: string
  celsius: number
}

export type BatteryStats = {
  percent: number
  charging: boolean
  source: string
}

export type ContainerStatus = {
  name: string
  status: string
  healthy: boolean
}

export type Snapshot = {
  collectedAt: string
  hostname: string
  cpu: CPUStats
  memory: MemoryStats
  storage: DiskStats[]
  network: NetworkStats[]
  temperatures: TemperatureStat[]
  battery?: BatteryStats
  docker: ContainerStatus[]
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

export type AlertSummary = {
  activeCount: number
  highestLevel: string
  latestMessage?: string
}

export type Bootstrap = {
  devices: Device[]
  device?: Device
  layout?: Layout
  alertSummary: AlertSummary
  events: EventRecord[]
}
