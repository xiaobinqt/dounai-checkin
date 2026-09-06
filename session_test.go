package main

import (
	"context"
	"image"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

func TestResponseBodyForLogDecodesEscapedUnicode(t *testing.T) {
	input := `{"ret":0,"msg":"\u68c0\u6d4b\u5230\u7b7e\u5230\u811a\u672c","svg":"<svg><text>\u9646</text></svg>"}`
	got := responseBodyForLog(input)
	for _, want := range []string{"检测到签到脚本", "<svg><text>陆</text></svg>"} {
		if !strings.Contains(got, want) {
			t.Fatalf("responseBodyForLog() = %q, want %q", got, want)
		}
	}
	if strings.Contains(got, `\u68c0`) {
		t.Fatalf("responseBodyForLog() kept escaped Chinese: %q", got)
	}
}

func TestSessionFetchesAndSolvesCheckInSVGChallenge(t *testing.T) {
	var server *httptest.Server
	server = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/captcha" || r.URL.Query().Get("type") != "checkin" || r.URL.Query().Get("_") == "" {
			t.Errorf("captcha URL = %q", r.URL.String())
		}
		if strings.Contains(r.URL.Query().Get("_"), "-") {
			t.Errorf("captcha cache-buster = %q, want decimal digits", r.URL.Query().Get("_"))
		}
		if r.Header.Get("Accept") != "application/json, text/javascript, */*; q=0.01" || r.Header.Get("X-Requested-With") != "XMLHttpRequest" {
			t.Errorf("captcha AJAX headers are incomplete: %v", r.Header)
		}
		if r.Referer() != server.URL+"/user/panel" || r.UserAgent() != browserUserAgent || r.Header.Get("Accept-Language") == "" {
			t.Errorf("captcha browser headers are incomplete: %v", r.Header)
		}
		for _, name := range []string{"Priority", "Sec-CH-UA", "Sec-CH-UA-Mobile", "Sec-CH-UA-Platform", "Sec-Fetch-Dest", "Sec-Fetch-Mode", "Sec-Fetch-Site"} {
			if r.Header.Get(name) != "" {
				t.Errorf("captcha header %s should not be set", name)
			}
		}
		assertCookie(t, r, "key", "value")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ret":1,"svg":"<svg><text>玖</text><text>-</text><text>伍</text><text>=</text></svg>","challenge":"test-challenge"}`))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	answer, err := session.fetchCaptcha(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if answer != "4" {
		t.Fatalf("fetchCaptcha() = %q, want 4", answer)
	}
	if session.lastCaptchaRawText != "玖-伍=" {
		t.Fatalf("captcha extracted text = %q, want 玖-伍=", session.lastCaptchaRawText)
	}
	if session.lastCaptchaCode != "4" {
		t.Fatalf("captcha code = %q, want 4", session.lastCaptchaCode)
	}
	if session.lastCaptchaChallenge != "test-challenge" {
		t.Fatalf("captcha challenge = %q, want test-challenge", session.lastCaptchaChallenge)
	}
	if !strings.Contains(session.lastCaptchaRequestURL, "/auth/captcha?type=checkin&_") {
		t.Fatalf("captcha request URL = %q", session.lastCaptchaRequestURL)
	}
}

func TestSessionCaptchaErrorIncludesDiagnosticsWithoutCookieValues(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ret":0,"msg":"验证码会话初始化失败","detail":"missing session"}`))
	}))
	defer server.Close()

	const secret = "private-cookie-value"
	session, err := NewSession(server.URL, "uid=123; key="+secret)
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	_, err = session.fetchCaptcha(context.Background(), nil)
	if err == nil {
		t.Fatal("fetchCaptcha() error = nil")
	}
	for _, want := range []string{"status=200 OK", "ret=0", `msg="验证码会话初始化失败"`, "cookie_names=[key uid]", "missing session"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("fetchCaptcha() error = %q, want %q", err, want)
		}
	}
	if strings.Contains(err.Error(), secret) {
		t.Fatal("fetchCaptcha() error leaked a cookie value")
	}
	if session.lastCaptchaRequestURL == "" {
		t.Fatal("captcha request URL was not retained for diagnostics")
	}
	if !strings.Contains(session.lastCaptchaResponseBody, `"ret":0`) {
		t.Fatalf("captcha response body = %q", session.lastCaptchaResponseBody)
	}
	if session.lastCaptchaRawText != "" || session.lastCaptchaCode != "" {
		t.Fatalf("rejected captcha diagnostics = raw %q, code %q; want both empty", session.lastCaptchaRawText, session.lastCaptchaCode)
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
		case "/auth/captcha":
			writeTestCaptcha(w)
		case "/user/checkin":
			if r.Method != http.MethodPost {
				t.Errorf("method = %s, want POST", r.Method)
			}
			if r.Referer() != server.URL+"/user/panel" {
				t.Errorf("Referer = %q, want %q", r.Referer(), server.URL+"/user/panel")
			}
			if r.Header.Get("Origin") != server.URL {
				t.Errorf("Origin = %q, want %q", r.Header.Get("Origin"), server.URL)
			}
			if r.Header.Get("X-Requested-With") != "XMLHttpRequest" {
				t.Errorf("X-Requested-With = %q", r.Header.Get("X-Requested-With"))
			}
			if r.Header.Get("Content-Type") != "application/x-www-form-urlencoded; charset=UTF-8" {
				t.Errorf("Content-Type = %q", r.Header.Get("Content-Type"))
			}
			if err := r.ParseForm(); err != nil {
				t.Fatal(err)
			}
			if got := r.Form.Get("captcha_code"); got != "1234" {
				t.Errorf("captcha_code = %q, want 1234", got)
			}
			if _, exists := r.Form["checkin_secret"]; !exists {
				t.Error("checkin_secret field is missing")
			}
			if got := r.Form.Get("checkin_secret"); got != "" {
				t.Errorf("checkin_secret = %q, want empty", got)
			}
			if got, want := r.Form.Get("checkin_token"), checkInToken(testCaptchaChallenge, "1234"); got != want {
				t.Errorf("checkin_token = %q, want %q", got, want)
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
	session.captchaRecognizer = testCaptchaRecognizer
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

func TestTryCheckInRefreshesUserPanelBeforePosting(t *testing.T) {
	requestOrder := make([]string, 0, 2)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestOrder = append(requestOrder, r.Method+" "+r.URL.Path)
		switch r.URL.Path {
		case "/user/panel":
			http.SetCookie(w, &http.Cookie{Name: "key", Value: "refreshed-key", Path: "/"})
			_, _ = w.Write([]byte("user panel"))
		case "/auth/captcha":
			writeTestCaptcha(w)
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
	session.captchaRecognizer = testCaptchaRecognizer

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
	wantOrder := []string{"GET /user/panel", "GET /auth/captcha", "POST /user/checkin"}
	if strings.Join(requestOrder, ",") != strings.Join(wantOrder, ",") {
		t.Fatalf("request order = %v, want %v", requestOrder, wantOrder)
	}
}

func TestTryCheckInDoesNotRetryAfterFailure(t *testing.T) {
	checkInRequests := 0
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/user/panel":
			_, _ = w.Write([]byte("user panel"))
		case "/auth/captcha":
			writeTestCaptcha(w)
		case "/user/checkin":
			checkInRequests++
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"ret":0,"msg":"验证码错误，还剩2次机会"}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	session.captchaRecognizer = testCaptchaRecognizer
	_, _, err = tryCheckIn(context.Background(), session)
	if err == nil {
		t.Fatal("tryCheckIn() error = nil")
	}
	if checkInRequests != 1 {
		t.Fatalf("check-in requests = %d, want 1", checkInRequests)
	}
	if !strings.Contains(session.lastCaptchaResponseBody, `"ret":1`) {
		t.Fatalf("captcha response body = %q", session.lastCaptchaResponseBody)
	}
	if !strings.Contains(session.lastCheckInResponseBody, "验证码错误，还剩2次机会") {
		t.Fatalf("check-in response body = %q", session.lastCheckInResponseBody)
	}
	if session.lastCaptchaRawText != "1234" || session.lastCaptchaCode != "1234" {
		t.Fatalf("captcha diagnostics = raw %q, code %q; want raw 1234, code 1234", session.lastCaptchaRawText, session.lastCaptchaCode)
	}
}

func TestSessionCheckInRejectsRetryMessage(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/auth/captcha" {
			writeTestCaptcha(w)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"msg":"请刷新页面后重试。","ret":1}`))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=value")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	session.captchaRecognizer = testCaptchaRecognizer

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

func TestSessionWritesChangedCookiesToSecureOutput(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.SetCookie(w, &http.Cookie{Name: "key", Value: "new-key", Path: "/"})
		_, _ = w.Write([]byte("account page"))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "uid=123; key=old-key; PHPSESSID=session-id")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	output := filepath.Join(t.TempDir(), "cookie")
	if err := session.SetCookieOutput(output); err != nil {
		t.Fatal(err)
	}

	changed, err := session.KeepAlive(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("KeepAlive() changed = false, want true")
	}

	contents, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := string(contents), "PHPSESSID=session-id; key=new-key; uid=123\n"; got != want {
		t.Fatalf("cookie output = %q, want %q", got, want)
	}
	info, err := os.Stat(output)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("cookie output mode = %o, want 600", got)
	}
}

func TestSessionDoesNotWriteUnchangedCookies(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("account page"))
	}))
	defer server.Close()

	session, err := NewSession(server.URL, "key=unchanged")
	if err != nil {
		t.Fatal(err)
	}
	session.client = server.Client()
	output := filepath.Join(t.TempDir(), "cookie")
	if err := session.SetCookieOutput(output); err != nil {
		t.Fatal(err)
	}
	if _, err := session.KeepAlive(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(output); !os.IsNotExist(err) {
		t.Fatalf("cookie output stat error = %v, want not-exist", err)
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

func writeTestCaptcha(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"ret":1,"svg":"<img src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\">","challenge":"` + testCaptchaChallenge + `"}`))
}

const testCaptchaChallenge = "1788660657.b09b14464c0edad9.5426597ac25f9c1857ae0fe2b20ebfaebe4a7120ed2f767e4539643d71a02dea"

func testCaptchaRecognizer(image.Image) (string, error) { return "1234", nil }
