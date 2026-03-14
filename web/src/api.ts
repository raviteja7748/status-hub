import type {
  AlertRule,
  Device,
  EventRecord,
  NotificationChannel,
  Widget,
} from './types'

export async function login(baseUrl: string, password: string) {
  const response = await fetch(`${baseUrl}/api/sessions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password }),
  })

  if (!response.ok) {
    throw new Error('Login failed')
  }

  return (await response.json()) as { token: string }
}

async function request<T>(baseUrl: string, token: string, path: string, init?: RequestInit) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...init?.headers,
    },
  })

  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`)
  }

  return (await response.json()) as T
}

export const api = {
  devices: (baseUrl: string, token: string) =>
    request<Device[]>(baseUrl, token, '/api/devices'),
  widgets: (baseUrl: string, token: string, deviceId: string) =>
    request<Widget[]>(baseUrl, token, `/api/widgets?deviceId=${deviceId}`),
  saveWidgets: (baseUrl: string, token: string, deviceId: string, widgets: Widget[]) =>
    request<{ ok: boolean }>(baseUrl, token, `/api/widgets?deviceId=${deviceId}`, {
      method: 'PUT',
      body: JSON.stringify(widgets),
    }),
  alerts: (baseUrl: string, token: string, deviceId: string) =>
    request<AlertRule[]>(baseUrl, token, `/api/alerts?deviceId=${deviceId}`),
  saveAlerts: (baseUrl: string, token: string, deviceId: string, rules: AlertRule[]) =>
    request<{ ok: boolean }>(baseUrl, token, `/api/alerts?deviceId=${deviceId}`, {
      method: 'PUT',
      body: JSON.stringify(rules),
    }),
  events: (baseUrl: string, token: string, deviceId: string) =>
    request<EventRecord[]>(baseUrl, token, `/api/events?deviceId=${deviceId}`),
  channels: (baseUrl: string, token: string) =>
    request<NotificationChannel[]>(baseUrl, token, '/api/notification-channels'),
  saveChannels: (baseUrl: string, token: string, channels: NotificationChannel[]) =>
    request<{ ok: boolean }>(baseUrl, token, '/api/notification-channels', {
      method: 'PUT',
      body: JSON.stringify(channels),
    }),
}

