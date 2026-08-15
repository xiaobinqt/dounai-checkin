package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

const maxResponseBody = 2 << 20

// Session stores the cookies obtained after a manual, captcha-protected login.
// Cookie values are never included in logs or error messages.
type Session struct {
	baseURL string
	client  *http.Client
	cookies map[string]*http.Cookie
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
	if method == http.MethodPost && path == "/user/checkin" {
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Referer", s.baseURL+"/user")
		req.Header.Set("X-Requested-With", "XMLHttpRequest")
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
	return resp, changed, nil
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
