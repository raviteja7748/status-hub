import type { Bootstrap } from './types'

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
  bootstrap: (baseUrl: string, token: string, deviceId?: string) =>
    request<Bootstrap>(
      baseUrl,
      token,
      `/api/bootstrap?target=mobile_web${deviceId ? `&deviceId=${deviceId}` : ''}`,
    ),
  acknowledgeEvent: (baseUrl: string, token: string, eventId: string) =>
    request<{ ok: boolean }>(baseUrl, token, `/api/events/${eventId}/ack`, { method: 'POST' }),
}
