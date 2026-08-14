package main

import (
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
