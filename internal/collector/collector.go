package collector

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/elite/status/internal/model"
	"github.com/gorilla/websocket"
	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/host"
	"github.com/shirou/gopsutil/v4/mem"
	"github.com/shirou/gopsutil/v4/net"
	"github.com/shirou/gopsutil/v4/sensors"
)

type Config struct {
	HubURL   string
	Token    string
	Name     string
	Interval time.Duration
}

type Collector struct {
	config Config
}

func New(config Config) *Collector {
	return &Collector{config: config}
}

func (c *Collector) Run(ctx context.Context) error {
	for {
		if err := c.connectAndStream(ctx); err != nil {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(5 * time.Second):
			}
		}
	}
}

func (c *Collector) connectAndStream(ctx context.Context) error {
	wsURL, err := collectorWSURL(c.config.HubURL, c.config.Token)
	if err != nil {
		return err
	}
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return err
	}
	defer conn.Close()

	hello := c.hello()
	if err := conn.WriteJSON(model.CollectorEnvelope{Type: "hello", Hello: &hello}); err != nil {
		return err
	}

	ticker := time.NewTicker(c.config.Interval)
	defer ticker.Stop()
	for {
		snapshot, err := c.collectSnapshot()
		if err == nil {
			if err := conn.WriteJSON(model.CollectorEnvelope{Type: "snapshot", Snapshot: &snapshot}); err != nil {
				return err
			}
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func collectorWSURL(baseURL, token string) (string, error) {
	parsed, err := url.Parse(strings.TrimRight(baseURL, "/"))
	if err != nil {
		return "", err
	}
	if parsed.Scheme == "https" {
		parsed.Scheme = "wss"
	} else {
		parsed.Scheme = "ws"
	}
	parsed.Path = "/ws/device"
	query := parsed.Query()
	query.Set("token", token)
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func (c *Collector) hello() model.CollectorHello {
	info, _ := host.Info()
	name := c.config.Name
	if name == "" {
		name = info.Hostname
	}
	return model.CollectorHello{
		Type:       "hello",
		DeviceName: name,
		Hostname:   info.Hostname,
		Capabilities: map[string]bool{
			"battery":     batteryPresent(),
			"docker":      dockerAvailable(),
			"temperature": true,
		},
		Metadata: map[string]string{
			"os":   info.OS,
			"host": info.Hostname,
		},
	}
}

func (c *Collector) collectSnapshot() (model.Snapshot, error) {
	info, err := host.Info()
	if err != nil {
		return model.Snapshot{}, err
	}
	cpuPct, _ := cpu.Percent(time.Second, false)
	vmem, _ := mem.VirtualMemory()
	partitions, _ := disk.Partitions(false)
	netStats, _ := net.IOCounters(true)
	temps, _ := sensors.SensorsTemperatures()

	snapshot := model.Snapshot{
		CollectedAt: time.Now().UTC(),
		Hostname:    info.Hostname,
		UptimeSec:   info.Uptime,
		CPU: model.CPUStats{
			Cores: len(cpuPct),
		},
		Memory: model.MemoryStats{
			UsedBytes:  vmem.Used,
			TotalBytes: vmem.Total,
			UsedPct:    vmem.UsedPercent,
		},
	}
	if len(cpuPct) > 0 {
		snapshot.CPU.UsagePercent = cpuPct[0]
	}
	for _, partition := range partitions {
		usage, err := disk.Usage(partition.Mountpoint)
		if err != nil {
			continue
		}
		snapshot.Storage = append(snapshot.Storage, model.DiskStats{
			Path:       partition.Mountpoint,
			UsedBytes:  usage.Used,
			TotalBytes: usage.Total,
			UsedPct:    usage.UsedPercent,
		})
	}
	for _, stat := range netStats {
		snapshot.Network = append(snapshot.Network, model.NetworkStats{
			Name:    stat.Name,
			RxBytes: stat.BytesRecv,
			TxBytes: stat.BytesSent,
		})
	}
	for _, temp := range temps {
		snapshot.Temperatures = append(snapshot.Temperatures, model.TemperatureStat{
			Name:    temp.SensorKey,
			Celsius: temp.Temperature,
		})
	}
	if battery := readBattery(); battery != nil {
		snapshot.Battery = battery
	}
	snapshot.Docker = readDockerContainers()

	return snapshot, nil
}

func batteryPresent() bool {
	entries, err := os.ReadDir("/sys/class/power_supply")
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if strings.HasPrefix(strings.ToUpper(entry.Name()), "BAT") {
			return true
		}
	}
	return false
}

func readBattery() *model.BatteryStats {
	entries, err := os.ReadDir("/sys/class/power_supply")
	if err != nil {
		return nil
	}
	var batteryDir string
	var acOnline bool
	for _, entry := range entries {
		if strings.HasPrefix(strings.ToUpper(entry.Name()), "BAT") {
			batteryDir = filepath.Join("/sys/class/power_supply", entry.Name())
		}
		if strings.Contains(strings.ToUpper(entry.Name()), "AC") || strings.Contains(strings.ToUpper(entry.Name()), "ADP") {
			value, _ := os.ReadFile(filepath.Join("/sys/class/power_supply", entry.Name(), "online"))
			acOnline = strings.TrimSpace(string(value)) == "1"
		}
	}
	if batteryDir == "" {
		return nil
	}
	capacityRaw, err := os.ReadFile(filepath.Join(batteryDir, "capacity"))
	if err != nil {
		return nil
	}
	statusRaw, _ := os.ReadFile(filepath.Join(batteryDir, "status"))
	percent, _ := strconv.ParseFloat(strings.TrimSpace(string(capacityRaw)), 64)
	status := strings.TrimSpace(string(statusRaw))
	source := "battery"
	if acOnline {
		source = "ac"
	}
	return &model.BatteryStats{
		Percent:  percent,
		Charging: strings.EqualFold(status, "Charging"),
		Source:   source,
	}
}

func dockerAvailable() bool {
	_, err := exec.LookPath("docker")
	return err == nil
}

func readDockerContainers() []model.ContainerStatus {
	if !dockerAvailable() {
		return nil
	}
	cmd := exec.Command("docker", "ps", "-a", "--format", "{{json .}}")
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	lines := bytes.Split(bytes.TrimSpace(out), []byte("\n"))
	containers := make([]model.ContainerStatus, 0, len(lines))
	for _, line := range lines {
		if len(line) == 0 {
			continue
		}
		var raw struct {
			Names      string `json:"Names"`
			Image      string `json:"Image"`
			State      string `json:"State"`
			Status     string `json:"Status"`
			RunningFor string `json:"RunningFor"`
		}
		if err := json.Unmarshal(line, &raw); err != nil {
			continue
		}
		containers = append(containers, model.ContainerStatus{
			Name:         raw.Names,
			Image:        raw.Image,
			State:        raw.State,
			Status:       raw.Status,
			Healthy:      !strings.Contains(strings.ToLower(raw.Status), "unhealthy"),
			RestartCount: 0,
		})
	}
	return containers
}

func formatDuration(seconds uint64) string {
	return fmt.Sprintf("%dh", seconds/3600)
}
