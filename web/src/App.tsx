import { useAuthStore } from './store'
import { Login } from './components/Login'
import { Dashboard } from './components/Dashboard'
import './App.css'

function App() {
  const { token } = useAuthStore()

  if (!token) {
    return <Login />
  }

  return <Dashboard />
}

export default App
