import { useStatus } from '../hooks/useStatus'
import { Hero } from './Hero'
import { Overview } from './Overview'
import { WidgetList } from './WidgetList'
import { AlertHistory } from './AlertHistory'
import { useAuthStore } from '../store'
import { useEffect, useState } from 'react'
import { LayoutDashboard, Bell, Settings } from 'lucide-react'

type Tab = 'dashboard' | 'alerts' | 'settings'

export function Dashboard() {
  const { data: bootstrap, isLoading, error } = useStatus()
  const { token, signOut } = useAuthStore()
  const [activeTab, setActiveTab] = useState<Tab>('dashboard')

  useEffect(() => {
    if (!error) return

    const message = (error as Error).message
    const isAuthFailure = message.includes('401') || message.includes('403')

    if (isAuthFailure) {
      signOut()
    }
  }, [error, signOut])

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
    <main className="shell has-nav">
      <Hero bootstrap={bootstrap} />
      
      {activeTab === 'dashboard' && (
        <div className="tab-content fade-in">
          {activeDevice && <Overview activeDevice={activeDevice} alertSummary={bootstrap?.alertSummary} />}
          <section className="content-grid single-column">
            <WidgetList bootstrap={bootstrap} activeDevice={activeDevice} />
          </section>
        </div>
      )}

      {activeTab === 'alerts' && (
        <div className="tab-content fade-in">
          <section className="content-grid single-column">
            <AlertHistory events={bootstrap?.events ?? []} />
          </section>
        </div>
      )}

      {activeTab === 'settings' && (
        <div className="tab-content fade-in">
          <article className="card panel">
            <h2>Settings</h2>
            <p className="lede">Management features coming soon in Phase 3.</p>
          </article>
        </div>
      )}

      <nav className="bottom-nav">
        <button 
          className={`nav-item ${activeTab === 'dashboard' ? 'active' : ''}`}
          onClick={() => setActiveTab('dashboard')}
        >
          <LayoutDashboard size={20} />
          <span>Dashboard</span>
        </button>
        <button 
          className={`nav-item ${activeTab === 'alerts' ? 'active' : ''}`}
          onClick={() => setActiveTab('alerts')}
        >
          <div className="icon-badge-container">
            <Bell size={20} />
            {(bootstrap?.alertSummary.activeCount ?? 0) > 0 && (
              <span className="badge">{bootstrap?.alertSummary.activeCount}</span>
            )}
          </div>
          <span>Alerts</span>
        </button>
        <button 
          className={`nav-item ${activeTab === 'settings' ? 'active' : ''}`}
          onClick={() => setActiveTab('settings')}
        >
          <Settings size={20} />
          <span>Settings</span>
        </button>
      </nav>
    </main>
  )
}
