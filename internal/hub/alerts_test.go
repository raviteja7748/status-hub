package hub

import (
	"testing"

	"github.com/elite/status/internal/model"
)

func TestEvaluateRuleTemperature(t *testing.T) {
	rule := model.AlertRule{Metric: "temperature", Condition: "gt", Threshold: 70}
	snapshot := model.Snapshot{
		Temperatures: []model.TemperatureStat{{Name: "cpu", Celsius: 82}},
	}
	fired, _ := EvaluateRule(rule, snapshot)
	if !fired {
		t.Fatal("expected temperature rule to fire")
	}
}

func TestEvaluateRuleBatteryLow(t *testing.T) {
	rule := model.AlertRule{Metric: "battery_low", Condition: "lt", Threshold: 25}
	snapshot := model.Snapshot{
		Battery: &model.BatteryStats{Percent: 11},
	}
	fired, _ := EvaluateRule(rule, snapshot)
	if !fired {
		t.Fatal("expected battery rule to fire")
	}
}
