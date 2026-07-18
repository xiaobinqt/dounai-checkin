package main

import "testing"

func TestNormalizeDouNaiURL(t *testing.T) {
	got, err := normalizeDouNaiURL(" https://example.com/ ")
	if err != nil {
		t.Fatal(err)
	}
	if want := "https://example.com"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}
