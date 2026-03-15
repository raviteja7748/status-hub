import { useStatus } from '../hooks/useStatus'
import { Hero } from './Hero'
import { Overview } from './Overview'
import { WidgetList } from './WidgetList'
import { AlertHistory } from './AlertHistory'
import { useAuthStore } from '../store'

export function Dashboard() {
  const { data: bootstrap, isLoading, error } = useStatus()
  const { token } = useAuthStore()

  if (!token) return null

  if (isLoading && !bootstrap) {
    return (
      <main className="shell">
        <div className="loading">Loading status...</div>
      </main>
    )
  }

  if (error) {
    return (
      <main className="shell">
        <p className="error">{(error as Error).message}</p>
      </main>
    )
  }

  const activeDevice = bootstrap?.devices.find((device) => device.id === bootstrap.device?.id) ?? bootstrap?.device

  return (
    <main className="shell">
      <Hero bootstrap={bootstrap} />
      {activeDevice && <Overview activeDevice={activeDevice} alertSummary={bootstrap?.alertSummary} />}
      <section className="content-grid single-column">
        <WidgetList bootstrap={bootstrap} activeDevice={activeDevice} />
        <AlertHistory events={bootstrap?.events ?? []} />
      </section>
    </main>
  )
}
