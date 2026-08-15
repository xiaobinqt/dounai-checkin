package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewSessionRequiresCookie(t *testing.T) {
	if _, err := NewSession("https://example.com", ""); err == nil {
		t.Fatal("NewSession() error = nil, want missing-cookie error")
	}
}

func TestNewSessionRequiresHTTPS(t *testing.T) {
	if _, err := NewSession("http://example.com", "key=value"); err == nil {
		t.Fatal("NewSession() error = nil, want HTTPS validation error")
	}
}

func TestSessionKeepAliveUpdatesCookiesForCheckIn(t *testing.T) {
	var server *httptest.Server
	server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/user":
			assertCookie(t, r, "uid", "123")
			assertCookie(t, r, "key", "old-key")
			http.SetCookie(w, &http.Cookie{Name: "key", Value: "new-key", Path: "/"})
			_, _ = w.Write([]byte("account page"))
		case "/user/checkin":
			if r.Method != http.MethodPost {
				t.Errorf("method = %s, want POST", r.Method)
			}
			if r.Referer() != server.URL+"/user" {
				t.Errorf("Referer = %q, want %q", r.Referer(), server.URL+"/user")
			}
			if r.Header.Get("X-Requested-With") != "XMLHttpRequest" {
				t.Errorf("X-Requested-With = %q", r.Header.Get("X-Requested-With"))
			}
			assertCookie(t, r, "key", "new-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"msg":"获得了 674 MB流量和1个豆丁，账号有效期及等级 1 时长延长 1.64 小时。","ret":1}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "uid=123; key=old-key; PHPSESSID=session-id")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	session.client.CheckRedirect = func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }
	changed, err := session.KeepAlive(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("KeepAlive() changed = false, want true")
	}

	msg, _, err := session.CheckIn(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if msg != "获得了 674 MB流量和1个豆丁，账号有效期及等级 1 时长延长 1.64 小时。" {
		t.Fatalf("CheckIn() message = %q", msg)
	}
}

func TestTryCheckInRefreshesUserPageBeforePosting(t *testing.T) {
	requestOrder := make([]string, 0, 2)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestOrder = append(requestOrder, r.Method+" "+r.URL.Path)
		switch r.URL.Path {
		case "/user":
			http.SetCookie(w, &http.Cookie{Name: "key", Value: "refreshed-key", Path: "/"})
			_, _ = w.Write([]byte("account page"))
		case "/user/checkin":
			assertCookie(t, r, "key", "refreshed-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"msg":"获得了 10 MB流量。","ret":1}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=old-key")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()

	msg, changed, err := tryCheckIn(context.Background(), session)
	if err != nil {
		t.Fatal(err)
	}
	if msg != "获得了 10 MB流量。" {
		t.Fatalf("tryCheckIn() message = %q", msg)
	}
	if !changed {
		t.Fatal("tryCheckIn() changed = false, want true")
	}
	wantOrder := []string{"GET /user", "POST /user/checkin"}
	if strings.Join(requestOrder, ",") != strings.Join(wantOrder, ",") {
		t.Fatalf("request order = %v, want %v", requestOrder, wantOrder)
	}
}

func TestSessionCheckInRejectsRetryMessage(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"msg":"请刷新页面后重试。","ret":1}`))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()

	msg, _, err := session.CheckIn(context.Background())
	if err == nil {
		t.Fatal("CheckIn() error = nil, want unconfirmed-response error")
	}
	if msg != "请刷新页面后重试。" {
		t.Fatalf("CheckIn() message = %q", msg)
	}
	if !strings.Contains(err.Error(), "check-in not confirmed") {
		t.Fatalf("CheckIn() error = %q", err)
	}
}

func TestKeepAliveReportsExpiredSessionWithoutLeakingCookie(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))
	defer server.Close()

	const secret = "private-cookie-value"
	session, err := NewSession(server.URL, "key="+secret)
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	_, err = session.KeepAlive(context.Background())
	if err == nil {
		t.Fatal("KeepAlive() error = nil, want session error")
	}
	if !strings.Contains(err.Error(), "session expired or invalid") {
		t.Fatalf("KeepAlive() error = %q", err)
	}
	if strings.Contains(err.Error(), secret) {
		t.Fatal("KeepAlive() error leaked the cookie value")
	}
}

func TestKeepAliveRejectsLoginRedirect(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", "/#login")
		w.WriteHeader(http.StatusFound)
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	session.client.CheckRedirect = func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }
	_, err = session.KeepAlive(context.Background())
	if err == nil || !strings.Contains(err.Error(), "session expired or invalid") {
		t.Fatalf("KeepAlive() error = %v, want expired session", err)
	}
}

func TestKeepAliveRejectsLoginPageWithOKStatus(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`<form><input name="captcha_code"><script>url: "/auth/login"</script></form>`))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	_, err = session.KeepAlive(context.Background())
	if err == nil || !strings.Contains(err.Error(), "session expired or invalid") {
		t.Fatalf("KeepAlive() error = %v, want expired session", err)
	}
}

func assertCookie(t *testing.T, r *http.Request, name, want string) {
	t.Helper()
	cookie, err := r.Cookie(name)
	if err != nil {
		t.Fatalf("cookie %q: %v", name, err)
	}
	if cookie.Value != want {
		t.Fatalf("cookie %q = %q, want %q", name, cookie.Value, want)
	}
}
