package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/Rican7/retry"
	"github.com/Rican7/retry/backoff"
	"github.com/Rican7/retry/strategy"
	jsoniter "github.com/json-iterator/go"
	"github.com/sirupsen/logrus"
)

const keepAliveInterval = 3 * time.Hour

func (s *Session) CheckIn(ctx context.Context) (string, bool, error) {
	resp, changed, err := s.do(ctx, http.MethodPost, "/user/checkin")
	if err != nil {
		return "", changed, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return "", changed, sessionHTTPError(resp)
	}
	body, err := readResponseBody(resp)
	if err != nil {
		return "", changed, err
	}
	if looksLikeLoginPage(body) {
		return "", changed, expiredSessionError(resp.Status)
	}

	var result Resp
	if err := jsoniter.Unmarshal(body, &result); err != nil {
		return "", changed, fmt.Errorf("decode check-in response: %w", err)
	}
	result.Msg = strings.TrimSpace(result.Msg)
	if err := validateCheckInResponse(result); err != nil {
		return result.Msg, changed, err
	}
	return result.Msg, changed, nil
}

func (s *Session) KeepAlive(ctx context.Context) (bool, error) {
	resp, changed, err := s.do(ctx, http.MethodGet, "/user")
	if err != nil {
		return changed, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return changed, sessionHTTPError(resp)
	}
	body, err := readResponseBody(resp)
	if err != nil {
		return changed, err
	}
	if looksLikeLoginPage(body) {
		return changed, expiredSessionError(resp.Status)
	}
	return changed, nil
}

func tryCheckIn(ctx context.Context, session *Session) (msg string, changed bool, err error) {
	action := func(attempt uint) error {
		// Match the browser flow: refresh the user page immediately before the
		// check-in request so the session and any rotated cookies are current.
		refreshed, refreshErr := session.KeepAlive(ctx)
		changed = changed || refreshed
		if refreshErr != nil {
			msg = ""
			err = refreshErr
			logrus.Errorf("refresh user page before check-in attempt %d failed: %v", attempt+1, err)
			return err
		}

		var attemptChanged bool
		msg, attemptChanged, err = session.CheckIn(ctx)
		changed = changed || attemptChanged
		if err != nil {
			logrus.Errorf("check-in attempt %d failed: %v", attempt+1, err)
		}
		return err
	}
	err = retry.Retry(
		action,
		strategy.Limit(3),
		strategy.Backoff(backoff.Fibonacci(8*time.Second)),
	)
	return msg, changed, err
}

func CheckInOnce(ctx context.Context, cookieHeader string) (string, bool, error) {
	session, err := NewSession(GetConf().DouNaiURL, cookieHeader)
	if err != nil {
		return "", false, err
	}
	return tryCheckIn(ctx, session)
}

func KeepAliveOnce(ctx context.Context, cookieHeader string) (bool, error) {
	session, err := NewSession(GetConf().DouNaiURL, cookieHeader)
	if err != nil {
		return false, err
	}
	return session.KeepAlive(ctx)
}

func AutoCheckIn(ctx context.Context, cookieHeader string) error {
	session, err := NewSession(GetConf().DouNaiURL, cookieHeader)
	if err != nil {
		return err
	}
	if _, err := session.KeepAlive(ctx); err != nil {
		_ = notifySessionFailure(err.Error())
		return err
	}

	logrus.Infof("dounai url: %s, check-in time: %s (UTC+8), keepalive interval: %s", GetConf().DouNaiURL, GetConf().CheckInTime, keepAliveInterval)
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	lastKeepAlive := time.Now()
	lastCheckInDate := ""

	for {
		select {
		case <-ctx.Done():
			return nil
		case now := <-ticker.C:
			if now.Sub(lastKeepAlive) >= keepAliveInterval {
				if _, err := session.KeepAlive(ctx); err != nil {
					_ = notifySessionFailure(err.Error())
					return err
				}
				lastKeepAlive = now
			}

			today := now.Format("2006-01-02")
			if now.Format("15:04") != GetConf().CheckInTime || lastCheckInDate == today {
				continue
			}
			lastCheckInDate = today
			msg, _, err := tryCheckIn(ctx, session)
			if err != nil {
				_ = notifyCheckInResult(false, checkInFailureMessage(msg, err))
				continue
			}
			_ = notifyCheckInResult(true, msg)
		}
	}
}
