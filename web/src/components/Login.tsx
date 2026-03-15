import React, { useState } from 'react'
import { login } from '../api'
import { useAuthStore } from '../store'

export function Login() {
  const { baseUrl, setBaseUrl, setToken } = useAuthStore()
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleLogin(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setLoading(true)
    setError('')
    try {
      const result = await login(baseUrl, password)
      setToken(result.token)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="shell auth-shell">
      <section className="auth-card">
        <p className="eyebrow">Status Hub</p>
        <h1>Phone view for your Linux status</h1>
        <p className="lede">
          This browser view is now the lighter companion. The main editing
          experience is moving to the Mac menu bar app.
        </p>
        <form onSubmit={handleLogin}>
          <label>
            Hub URL
            <input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} />
          </label>
          <label>
            Admin password
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>
          <button type="submit" disabled={loading}>
            {loading ? 'Connecting...' : 'Connect'}
          </button>
        </form>
        {error ? <p className="error">{error}</p> : null}
      </section>
    </main>
  )
}
