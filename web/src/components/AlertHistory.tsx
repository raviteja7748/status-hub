import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import type { EventRecord } from '../types'
import { api } from '../api'
import { useAuthStore } from '../store'
import { CheckCircle2, Clock, AlertCircle, Info, ShieldAlert } from 'lucide-react'

interface AlertHistoryProps {
  events: EventRecord[]
}

export function AlertHistory({ events }: AlertHistoryProps) {
  const { baseUrl, token } = useAuthStore()
  const queryClient = useQueryClient()
  const [busyEventId, setBusyEventId] = useState('')

  const acknowledgeMutation = useMutation({
    mutationFn: (eventId: string) => api.acknowledgeEvent(baseUrl, token, eventId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['bootstrap'] })
    },
    onSettled: () => {
      setBusyEventId('')
    },
  })

  const handleAcknowledge = (eventId: string) => {
    setBusyEventId(eventId)
    acknowledgeMutation.mutate(eventId)
  }

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical': return <ShieldAlert size={18} color="#ef4444" />
      case 'warning': return <AlertCircle size={18} color="#f59e0b" />
      case 'info': return <Info size={18} color="#3b82f6" />
      default: return <Info size={18} />
    }
  }

  return (
    <article className="card panel">
      <div className="panel-head">
        <div>
          <p className="eyebrow">Alerts</p>
          <h2>Recent alert history</h2>
        </div>
      </div>
      <div className="event-list">
        {events.map((eventItem) => (
          <div key={eventItem.id} className={`event-row ${eventItem.severity}`}>
            <div style={{ display: 'flex', gap: '12px' }}>
              <div style={{ marginTop: '4px' }}>
                {getSeverityIcon(eventItem.severity)}
              </div>
              <div style={{ flex: 1 }}>
                <strong>{eventItem.title}</strong>
                <p>{eventItem.body}</p>
                <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '4px', fontSize: '0.8rem', color: '#888' }}>
                  <Clock size={12} />
                  <span>{new Date(eventItem.createdAt).toLocaleString()}</span>
                </div>
                <div style={{ marginTop: '8px' }}>
                  {eventItem.acknowledgedAt ? (
                    <span className="acked">
                      <CheckCircle2 size={12} style={{ marginRight: '4px' }} />
                      Acknowledged
                    </span>
                  ) : (
                    <button
                      className="secondary small"
                      onClick={() => handleAcknowledge(eventItem.id)}
                      disabled={busyEventId === eventItem.id}
                    >
                      {busyEventId === eventItem.id ? 'Saving...' : 'Acknowledge'}
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
        ))}
        {events.length === 0 && <p className="empty-state">No recent alerts</p>}
      </div>
    </article>
  )
}
