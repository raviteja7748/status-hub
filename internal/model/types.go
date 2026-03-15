package model

import "time"

type AuthRequest struct {
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
}

type ClientTokenCreateRequest struct {
	Name string `json:"name"`
	Kind string `json:"kind"`
}

type ClientToken struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Kind       string     `json:"kind"`
	Token      string     `json:"token,omitempty"`
	CreatedAt  time.Time  `json:"createdAt"`
	LastUsedAt *time.Time `json:"lastUsedAt,omitempty"`
	Revoked    bool       `json:"revoked"`
}

type Device struct {
	ID           string            `json:"id"`
	Name         string            `json:"name"`
	Token        string            `json:"-"`
	LastSeen     time.Time         `json:"lastSeen"`
	Online       bool              `json:"online"`
	Capabilities map[string]bool   `json:"capabilities"`
	Snapshot     *Snapshot         `json:"snapshot,omitempty"`
	AlertState   string            `json:"alertState"`
	Metadata     map[string]string `json:"metadata,omitempty"`
}

type Snapshot struct {
	CollectedAt  time.Time         `json:"collectedAt"`
	Hostname     string            `json:"hostname"`
	UptimeSec    uint64            `json:"uptimeSec"`
	CPU          CPUStats          `json:"cpu"`
	Memory       MemoryStats       `json:"memory"`
	Storage      []DiskStats       `json:"storage"`
	Network      []NetworkStats    `json:"network"`
	Temperatures []TemperatureStat `json:"temperatures"`
	Battery      *BatteryStats     `json:"battery,omitempty"`
	Docker       []ContainerStatus `json:"docker"`
}

type CPUStats struct {
	UsagePercent float64 `json:"usagePercent"`
	Cores        int     `json:"cores"`
}

type MemoryStats struct {
	UsedBytes  uint64  `json:"usedBytes"`
	TotalBytes uint64  `json:"totalBytes"`
	UsedPct    float64 `json:"usedPct"`
}

type DiskStats struct {
	Path       string  `json:"path"`
	UsedBytes  uint64  `json:"usedBytes"`
	TotalBytes uint64  `json:"totalBytes"`
	UsedPct    float64 `json:"usedPct"`
}

type NetworkStats struct {
	Name      string `json:"name"`
	RxBytes   uint64 `json:"rxBytes"`
	TxBytes   uint64 `json:"txBytes"`
	IsDefault bool   `json:"isDefault"`
}

type TemperatureStat struct {
	Name    string  `json:"name"`
	Celsius float64 `json:"celsius"`
}

type BatteryStats struct {
	Percent    float64 `json:"percent"`
	Charging   bool    `json:"charging"`
	Source     string  `json:"source"`
	TimeToFull string  `json:"timeToFull,omitempty"`
	TimeLeft   string  `json:"timeLeft,omitempty"`
}

type ContainerStatus struct {
	Name         string `json:"name"`
	Image        string `json:"image"`
	State        string `json:"state"`
	Status       string `json:"status"`
	Healthy      bool   `json:"healthy"`
	RestartCount int    `json:"restartCount"`
}

type Widget struct {
	ID       string                 `json:"id"`
	Kind     string                 `json:"kind"`
	DeviceID string                 `json:"deviceId"`
	Title    string                 `json:"title"`
	Visible  bool                   `json:"visible"`
	Order    int                    `json:"order"`
	Size     string                 `json:"size"`
	Settings map[string]interface{} `json:"settings"`
}

type AlertRule struct {
	ID              string   `json:"id"`
	DeviceID        string   `json:"deviceId"`
	Title           string   `json:"title"`
	Metric          string   `json:"metric"`
	Condition       string   `json:"condition"`
	Threshold       float64  `json:"threshold"`
	DurationSeconds int      `json:"duration"`
	Severity        string   `json:"severity"`
	Channels        []string `json:"channels"`
	Enabled         bool     `json:"enabled"`
	ResolveBehavior string   `json:"resolveBehavior"`
}

type Event struct {
	ID             string     `json:"id"`
	DeviceID       string     `json:"deviceId"`
	AlertRuleID    string     `json:"alertRuleId,omitempty"`
	Type           string     `json:"type"`
	Severity       string     `json:"severity"`
	Title          string     `json:"title"`
	Body           string     `json:"body"`
	CreatedAt      time.Time  `json:"createdAt"`
	ResolvedAt     *time.Time `json:"resolvedAt,omitempty"`
	AcknowledgedAt *time.Time `json:"acknowledgedAt,omitempty"`
	AcknowledgedBy string     `json:"acknowledgedBy,omitempty"`
	DedupeKey      string     `json:"dedupeKey"`
}

type NotificationChannel struct {
	ID      string                 `json:"id"`
	Kind    string                 `json:"kind"`
	Name    string                 `json:"name"`
	Enabled bool                   `json:"enabled"`
	Config  map[string]interface{} `json:"config"`
}

type Layout struct {
	ID        string    `json:"id"`
	DeviceID  string    `json:"deviceId"`
	Target    string    `json:"target"`
	Widgets   []Widget  `json:"widgets"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type AlertSummary struct {
	ActiveCount   int    `json:"activeCount"`
	HighestLevel  string `json:"highestLevel"`
	LatestMessage string `json:"latestMessage,omitempty"`
}

type BootstrapResponse struct {
	Devices      []Device     `json:"devices"`
	Device       *Device      `json:"device,omitempty"`
	Layout       *Layout      `json:"layout,omitempty"`
	AlertSummary AlertSummary `json:"alertSummary"`
	Events       []Event      `json:"events"`
}

type CollectorHello struct {
	Type         string            `json:"type"`
	DeviceName   string            `json:"deviceName"`
	Hostname     string            `json:"hostname"`
	Capabilities map[string]bool   `json:"capabilities"`
	Metadata     map[string]string `json:"metadata,omitempty"`
}

type CollectorEnvelope struct {
	Type     string          `json:"type"`
	Snapshot *Snapshot       `json:"snapshot,omitempty"`
	Hello    *CollectorHello `json:"hello,omitempty"`
}

type StreamMessage struct {
	Type    string      `json:"type"`
	Device  *Device     `json:"device,omitempty"`
	Event   *Event      `json:"event,omitempty"`
	Payload interface{} `json:"payload,omitempty"`
}
