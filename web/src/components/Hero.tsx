import { useAppStore, useAuthStore } from '../store'
import type { Bootstrap } from '../types'
import { LogOut, Monitor } from 'lucide-react'

interface HeroProps {
  bootstrap?: Bootstrap
}

export function Hero({ bootstrap }: HeroProps) {
  const { signOut } = useAuthStore()
  const { selectedDeviceId, setSelectedDeviceId } = useAppStore()

  return (
    <section className="hero-panel">
      <div>
        <p className="eyebrow">Status Hub</p>
        <h1>Mobile companion</h1>
        <p className="lede">
          Quick status, alert history, and light controls while the Mac menu
          bar becomes the main control center.
        </p>
      </div>
      <div className="hero-side">
        <label>
          <Monitor size={16} style={{ marginRight: '8px', verticalAlign: 'middle' }} />
          Device
          <select
            value={selectedDeviceId}
            onChange={(event) => setSelectedDeviceId(event.target.value)}
          >
            {(bootstrap?.devices ?? []).map((device) => (
              <option key={device.id} value={device.id}>
                {device.name}
              </option>
            ))}
          </select>
        </label>
        <button
          className="secondary"
          onClick={signOut}
        >
          <LogOut size={16} />
          Sign out
        </button>
      </div>
    </section>
  )
}
