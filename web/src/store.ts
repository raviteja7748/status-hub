import { create } from 'zustand'

interface AuthState {
  baseUrl: string
  token: string
  setBaseUrl: (url: string) => void
  setToken: (token: string) => void
  signOut: () => void
}

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

export const useAuthStore = create<AuthState>((set) => ({
  baseUrl: resolveDefaultBaseUrl(),
  token: localStorage.getItem('status.token') ?? '',
  setBaseUrl: (url) => {
    localStorage.setItem('status.baseUrl', url)
    set({ baseUrl: url })
  },
  setToken: (token) => {
    localStorage.setItem('status.token', token)
    set({ token })
  },
  signOut: () => {
    localStorage.removeItem('status.token')
    set({ token: '' })
    useAppStore.setState({ selectedDeviceId: '' })
  },
}))

interface AppState {
  selectedDeviceId: string
  setSelectedDeviceId: (id: string) => void
}

export const useAppStore = create<AppState>((set) => ({
  selectedDeviceId: '',
  setSelectedDeviceId: (id) => set({ selectedDeviceId: id }),
}))
