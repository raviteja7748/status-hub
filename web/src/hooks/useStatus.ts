import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import ReconnectingWebSocket from 'reconnecting-websocket'
import { api } from '../api'
import { useAppStore, useAuthStore } from '../store'

export function useStatus() {
  const { baseUrl, token } = useAuthStore()
  const { selectedDeviceId, setSelectedDeviceId } = useAppStore()
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['bootstrap', selectedDeviceId],
    queryFn: async () => {
      const next = await api.bootstrap(baseUrl, token, selectedDeviceId)
      if (!selectedDeviceId && next.device?.id) {
        setSelectedDeviceId(next.device.id)
      }
      return next
    },
    enabled: !!token,
  })

  useEffect(() => {
    if (!token) return

    const wsUrl = baseUrl.replace(/^http/, 'ws') + `/ws/stream?token=${token}`
    const rws = new ReconnectingWebSocket(wsUrl)

    rws.onmessage = () => {
      // Invalidate the query to trigger a refresh
      void queryClient.invalidateQueries({ queryKey: ['bootstrap'] })
    }

    return () => {
      rws.close()
    }
  }, [token, baseUrl, queryClient])

  return query
}
