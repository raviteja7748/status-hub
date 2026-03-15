# UI Enhancement Plan - Status Hub

This document outlines the current state of the Status Hub web interface and provides a roadmap for transforming it into a more robust, feature-rich "mobile companion" and dashboard.

## 1. Current State Analysis

### 1.1 Architecture & Tech Stack
- **Framework:** React 19 (using some experimental hooks like `useEffectEvent`).
- **Build Tool:** Vite.
- **Language:** TypeScript.
- **Styling:** Custom CSS (single `App.css`) with a focus on a dark, modern aesthetic.
- **State Management:** Local `useState` and `useEffect` hooks; monolithic `App.tsx`.
- **Data Fetching:** Custom `fetch` wrappers in `api.ts`; re-fetching the entire "bootstrap" payload on every WebSocket message.
- **Real-time:** WebSocket stream triggers full data refresh.

### 1.2 User Interface Components
- **Auth:** Basic login screen with URL and password fields.
- **Hero:** Informational panel with device selector and sign-out.
- **Overview Grid:** High-level stats (Status, CPU, Memory, Alert Count).
- **Widget List:** Vertical list of active widgets (Overview, Temp, Battery, Docker).
- **Alert History:** List of recent events with an "Acknowledge" action.

### 1.3 Identified Limitations
- **Monolithic Component:** `App.tsx` handles everything from auth to dashboard logic, making it hard to maintain.
- **Data Inefficiency:** Re-fetching the entire state for every update is wasteful as the codebase grows.
- **Limited Visuals:** Widgets are currently text-heavy and lack visual indicators like gauges, sparklines, or status icons.
- **Missing Management UI:** API support exists for managing alert rules and notification channels, but there is no UI to configure them.
- **Mobile Experience:** While responsive, it lacks the "app-like" feel (e.g., bottom navigation, pull-to-refresh).

---

## 2. Proposed Enhancements

### 2.1 UI/UX Refinement
- **Dashboard Layout:**
  - Implement a grid-based dashboard with drag-and-drop or configurable ordering.
  - Use visual "Status Rings" or "Gauges" for CPU and Memory usage.
  - Add sparklines to show trends for metrics like temperature or load over the last hour.
- **Widget Upgrades:**
  - **Storage:** Show bar charts for partition usage.
  - **Network:** Show real-time up/down speeds.
  - **Multi-sensor Temp:** Support displaying multiple sensors or picking a "primary" one.
  - **Docker:** Add "Start/Stop" buttons and more detailed health info.
- **App-like Navigation:**
  - Bottom navigation bar for "Dashboard", "Alerts", and "Settings".
  - Dedicated "Settings" view to manage:
    - Alert Rules (Edit thresholds, conditions).
    - Notification Channels (Configure ntfy.sh topics, etc.).
    - Client Tokens (Manage tokens for Mac/Mobile).
- **Theming:** Formalize CSS variables for easy dark/light mode switching (currently dark-only).

### 2.2 Technical Improvements
- **Componentization:**
  - Break `App.tsx` into: `AuthProvider`, `DeviceProvider`, `DashboardLayout`, `WidgetRegistry`, `AlertCenter`, and `SettingsPanel`.
- **State Management:**
  - Adopt **TanStack Query** (React Query) for caching and optimistic updates.
  - Use **Zustand** or simple **React Context** for global app state (selected device, auth token).
- **WebSocket Optimization:**
  - Instead of re-fetching everything, process incoming WebSocket messages to update the local cache incrementally.
  - Implement a robust auto-reconnect strategy with exponential backoff.
- **Standardization:**
  - Replace experimental hooks with stable alternatives.
  - Use a lightweight component library (e.g., **Radix UI**) for accessible primitives like Dialogs, Popovers, and Tabs.

---

## 3. Tech Stack Roadmap

| Layer | Recommended Technology |
| :--- | :--- |
| **Framework** | React 19 (Stable) |
| **State Management** | TanStack Query (Server State) + Zustand (Client State) |
| **Styling** | Modern CSS (Modules or Tailwind) + Radix UI Primitives |
| **Icons** | Lucide React |
| **Charts/Visuals** | Recharts or simple SVG-based components |
| **Real-time** | Standard WebSockets with `reconnecting-websocket` |
| **Validation** | Zod (for API response validation) |

---

## 4. Implementation Phases

1.  **Phase 1: Foundation (Refactoring)** - Componentize `App.tsx`, introduce TanStack Query, and clean up auth logic.
2.  **Phase 2: Visual Polish** - Implement gauges, sparklines, and better grid layouts for widgets.
3.  **Phase 3: Management Features** - Build the "Settings" views for alert rules and notification channels.
4.  **Phase 4: Optimization** - Refine WebSocket message handling for incremental updates and "App-like" mobile interactions.
