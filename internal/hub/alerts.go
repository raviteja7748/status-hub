package hub

import (
	"fmt"
	"strings"
	"time"

	"github.com/elite/status/internal/model"
	"github.com/google/uuid"
)

func EvaluateRule(rule model.AlertRule, snapshot model.Snapshot) (bool, string) {
	switch rule.Metric {
	case "temperature":
		var hottest float64
		for _, sensor := range snapshot.Temperatures {
			if sensor.Celsius > hottest {
				hottest = sensor.Celsius
			}
		}
		if compareValue(hottest, rule.Condition, rule.Threshold) {
			return true, fmt.Sprintf("Temperature reached %.1fC", hottest)
		}
	case "battery_low":
		if snapshot.Battery != nil && compareValue(snapshot.Battery.Percent, rule.Condition, rule.Threshold) {
			return true, fmt.Sprintf("Battery dropped to %.0f%%", snapshot.Battery.Percent)
		}
	case "charging_full":
		if snapshot.Battery != nil && snapshot.Battery.Charging && snapshot.Battery.Percent >= rule.Threshold {
			return true, fmt.Sprintf("Battery is %.0f%% and still charging", snapshot.Battery.Percent)
		}
	case "disk_used":
		var fullest model.DiskStats
		for _, disk := range snapshot.Storage {
			if disk.UsedPct > fullest.UsedPct {
				fullest = disk
			}
		}
		if compareValue(fullest.UsedPct, rule.Condition, rule.Threshold) {
			return true, fmt.Sprintf("Disk %s is %.1f%% full", fullest.Path, fullest.UsedPct)
		}
	case "docker_unhealthy":
		for _, container := range snapshot.Docker {
			if !container.Healthy || strings.Contains(strings.ToLower(container.Status), "unhealthy") {
				return true, fmt.Sprintf("Container %s reports %s", container.Name, container.Status)
			}
		}
	}

	return false, ""
}

func compareValue(current float64, condition string, threshold float64) bool {
	switch condition {
	case "gt":
		return current > threshold
	case "gte":
		return current >= threshold
	case "lt":
		return current < threshold
	case "lte":
		return current <= threshold
	default:
		return false
	}
}

func DefaultWidgets(deviceID string) []model.Widget {
	return []model.Widget{
		newWidget(deviceID, "overview", "Overview", 0, "wide"),
		newWidget(deviceID, "cpu-memory", "CPU + Memory", 1, "medium"),
		newWidget(deviceID, "storage", "Storage", 2, "medium"),
		newWidget(deviceID, "network", "Network", 3, "medium"),
		newWidget(deviceID, "temperature", "Temperature", 4, "small"),
		newWidget(deviceID, "battery", "Battery + Power", 5, "small"),
		newWidget(deviceID, "docker", "Docker", 6, "wide"),
	}
}

func DefaultLayoutWidgets(deviceID, target string) []model.Widget {
	switch target {
	case "mobile_web":
		return []model.Widget{
			newWidget(deviceID, "overview", "Overview", 0, "wide"),
			newWidget(deviceID, "temperature", "Temperature", 1, "small"),
			newWidget(deviceID, "battery", "Battery + Power", 2, "small"),
			newWidget(deviceID, "docker", "Docker", 3, "wide"),
		}
	default:
		return DefaultWidgets(deviceID)
	}
}

func newWidget(deviceID, kind, title string, order int, size string) model.Widget {
	return model.Widget{
		ID:       uuid.NewString(),
		Kind:     kind,
		DeviceID: deviceID,
		Title:    title,
		Visible:  true,
		Order:    order,
		Size:     size,
		Settings: map[string]interface{}{},
	}
}

func DefaultAlertRules(deviceID string) []model.AlertRule {
	return []model.AlertRule{
		newRule(deviceID, "High Temperature", "temperature", "gt", 80, "critical"),
		newRule(deviceID, "Battery Low", "battery_low", "lt", 20, "warning"),
		newRule(deviceID, "Charging Full", "charging_full", "gte", 98, "info"),
		newRule(deviceID, "Disk Almost Full", "disk_used", "gt", 85, "warning"),
		newRule(deviceID, "Container Unhealthy", "docker_unhealthy", "gt", 0, "critical"),
	}
}

func newRule(deviceID, title, metric, condition string, threshold float64, severity string) model.AlertRule {
	return model.AlertRule{
		ID:              uuid.NewString(),
		DeviceID:        deviceID,
		Title:           title,
		Metric:          metric,
		Condition:       condition,
		Threshold:       threshold,
		DurationSeconds: 0,
		Severity:        severity,
		Channels:        []string{},
		Enabled:         true,
		ResolveBehavior: "auto",
	}
}

func NewEvent(deviceID string, rule model.AlertRule, body string) model.Event {
	return model.Event{
		ID:          uuid.NewString(),
		DeviceID:    deviceID,
		AlertRuleID: rule.ID,
		Type:        "alert",
		Severity:    rule.Severity,
		Title:       rule.Title,
		Body:        body,
		CreatedAt:   time.Now().UTC(),
		DedupeKey:   deviceID + ":" + rule.ID,
	}
}
