package main

import (
	"fmt"
	"testing"
	"time"
)

func TestShouldNotifySessionFailure(t *testing.T) {
	tests := []struct {
		name string
		hour int
		want bool
	}{
		{name: "midnight", hour: 0, want: false},
		{name: "before nine", hour: 8, want: false},
		{name: "nine", hour: 9, want: true},
		{name: "evening", hour: 23, want: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			now := time.Date(2026, time.August, 14, tt.hour, 0, 0, 0, shanghaiTimeZone)
			if got := shouldNotifySessionFailure(now); got != tt.want {
				t.Fatalf("shouldNotifySessionFailure(%02d:00) = %t, want %t", tt.hour, got, tt.want)
			}
		})
	}
}

func TestCheckInFailureMessagePrefersServerMessage(t *testing.T) {
	got := checkInFailureMessage("请刷新页面后重试。", fmt.Errorf("check-in not confirmed: ret=1"))
	if got != "请刷新页面后重试。" {
		t.Fatalf("checkInFailureMessage() = %q", got)
	}
}

func TestCheckInNotificationTitle(t *testing.T) {
	tests := []struct {
		name    string
		success bool
		message string
		want    string
	}{
		{name: "reward", success: true, message: "获得了 674 MB流量。", want: "✅ 豆奶签到成功"},
		{name: "already checked in", success: true, message: "您今天已经续过命了。", want: "☑️ 豆奶今日已签到"},
		{name: "retry requested", message: "请刷新页面后重试。", want: "❌ 豆奶签到失败"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := checkInNotificationTitle(tt.success, tt.message); got != tt.want {
				t.Fatalf("checkInNotificationTitle() = %q, want %q", got, tt.want)
			}
		})
	}
}
