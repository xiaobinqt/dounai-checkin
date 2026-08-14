package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSendBark(t *testing.T) {
	originalConf := *GetConf()
	defer func() { *GetConf() = originalConf }()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/device-key" {
			t.Errorf("path = %q, want %q", r.URL.Path, "/device-key")
		}

		var payload barkRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("decode request: %v", err)
		}
		if payload.Title != "签到成功" || payload.Body != "获得 10MB" || payload.Group != "豆奶签到" {
			t.Errorf("unexpected payload: %+v", payload)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":200,"message":"success"}`))
	}))
	defer server.Close()

	SetBarkKey("device-key")
	SetBarkServer(server.URL)
	if err := SendBark("签到成功", "获得 10MB"); err != nil {
		t.Fatal(err)
	}
}

func TestSendBarkRejectsFailureResponse(t *testing.T) {
	originalConf := *GetConf()
	defer func() { *GetConf() = originalConf }()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"code":400,"message":"invalid key"}`))
	}))
	defer server.Close()

	SetBarkKey("bad-key")
	SetBarkServer(server.URL)
	if err := SendBark("签到失败", "登录失败"); err == nil {
		t.Fatal("SendBark() error = nil, want an error")
	}
}
