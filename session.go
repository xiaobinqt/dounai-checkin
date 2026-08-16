package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const maxResponseBody = 2 << 20

const browserUserAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

// Session stores the cookies obtained after a manual, captcha-protected login.
// Cookie values are never included in logs or error messages.
type Session struct {
	baseURL string
	client  *http.Client
	cookies map[string]*http.Cookie

	cookieOutput string
}

// SetCookieOutput configures an optional file that receives the complete
// Cookie request header whenever the server rotates or deletes a cookie.
// The file is only written after a response actually changes the cookie set.
func (s *Session) SetCookieOutput(path string) error {
	path = strings.TrimSpace(path)
	if path == "" {
		s.cookieOutput = ""
		return nil
	}

	parent := filepath.Dir(path)
	info, err := os.Stat(parent)
	if err != nil {
		return fmt.Errorf("access cookie output directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("cookie output parent %q is not a directory", parent)
	}
	s.cookieOutput = path
	return nil
}

func NewSession(baseURL, cookieHeader string) (*Session, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if err := validateSessionURL(baseURL); err != nil {
		return nil, err
	}

	request := &http.Request{Header: http.Header{"Cookie": []string{strings.TrimSpace(cookieHeader)}}}
	parsedCookies := request.Cookies()
	if len(parsedCookies) == 0 {
		return nil, fmt.Errorf("dounai_cookie is required and must contain a valid Cookie header")
	}

	cookies := make(map[string]*http.Cookie, len(parsedCookies))
	for _, cookie := range parsedCookies {
		if cookie.Name == "" {
			continue
		}
		copy := *cookie
		cookies[cookie.Name] = &copy
	}
	if len(cookies) == 0 {
		return nil, fmt.Errorf("dounai_cookie does not contain any usable cookies")
	}

	return &Session{
		baseURL: baseURL,
		client: &http.Client{
			Timeout: 15 * time.Second,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		cookies: cookies,
	}, nil
}

func (s *Session) newRequest(ctx context.Context, method, path string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, s.baseURL+path, nil)
	if err != nil {
		return nil, fmt.Errorf("create %s request: %w", path, err)
	}

	names := make([]string, 0, len(s.cookies))
	for name := range s.cookies {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		req.AddCookie(s.cookies[name])
	}
	req.Header.Set("User-Agent", browserUserAgent)
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	if method == http.MethodPost && path == "/user/checkin" {
		// Match the jQuery request made by the check-in button on /user/panel.
		req.Header.Set("Accept", "application/json, text/javascript, */*; q=0.01")
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
		req.Header.Set("Origin", s.baseURL)
		req.Header.Set("Referer", s.baseURL+"/user/panel")
		req.Header.Set("X-Requested-With", "XMLHttpRequest")
	} else {
		req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	}
	return req, nil
}

func (s *Session) do(ctx context.Context, method, path string) (*http.Response, bool, error) {
	req, err := s.newRequest(ctx, method, path)
	if err != nil {
		return nil, false, err
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, false, fmt.Errorf("request %s: %w", path, err)
	}

	changed := false
	for _, cookie := range resp.Cookies() {
		if cookie.Name == "" {
			continue
		}
		if cookie.MaxAge < 0 || (!cookie.Expires.IsZero() && cookie.Expires.Before(time.Now())) {
			if _, exists := s.cookies[cookie.Name]; exists {
				delete(s.cookies, cookie.Name)
				changed = true
			}
			continue
		}
		previous, exists := s.cookies[cookie.Name]
		if !exists || previous.Value != cookie.Value {
			changed = true
		}
		copy := *cookie
		s.cookies[cookie.Name] = &copy
	}
	if changed {
		if err := s.writeCookieOutput(); err != nil {
			_ = resp.Body.Close()
			return nil, changed, err
		}
	}
	return resp, changed, nil
}

func (s *Session) writeCookieOutput() error {
	if s.cookieOutput == "" {
		return nil
	}

	names := make([]string, 0, len(s.cookies))
	for name := range s.cookies {
		names = append(names, name)
	}
	sort.Strings(names)

	parts := make([]string, 0, len(names))
	for _, name := range names {
		parts = append(parts, (&http.Cookie{Name: name, Value: s.cookies[name].Value}).String())
	}

	file, err := os.OpenFile(s.cookieOutput, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("open cookie output: %w", err)
	}
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return fmt.Errorf("secure cookie output: %w", err)
	}
	if _, err := io.WriteString(file, strings.Join(parts, "; ")+"\n"); err != nil {
		_ = file.Close()
		return fmt.Errorf("write cookie output: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close cookie output: %w", err)
	}
	return nil
}

func readResponseBody(resp *http.Response) ([]byte, error) {
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	return body, nil
}

func sessionHTTPError(resp *http.Response) error {
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden || isLoginRedirect(resp) {
		return expiredSessionError(resp.Status)
	}
	return fmt.Errorf("server returned HTTP %s", resp.Status)
}

func expiredSessionError(status string) error {
	return fmt.Errorf("session expired or invalid (HTTP %s); log in manually and update DOUNAI_COOKIE", status)
}

func looksLikeLoginPage(body []byte) bool {
	lowerBody := strings.ToLower(string(body))
	return strings.Contains(lowerBody, "/auth/login") && strings.Contains(lowerBody, "captcha_code")
}

func isLoginRedirect(resp *http.Response) bool {
	if resp.StatusCode < http.StatusMultipleChoices || resp.StatusCode >= http.StatusBadRequest {
		return false
	}
	location, err := resp.Location()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(location.Path), "login") || strings.Contains(strings.ToLower(location.Fragment), "login")
}

func validateSessionURL(rawURL string) error {
	parsedURL, err := url.ParseRequestURI(rawURL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host == "" {
		return fmt.Errorf("invalid dounai_url %q, expected an https URL", rawURL)
	}
	return nil
}
