package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"github.com/Rican7/retry"
	"github.com/Rican7/retry/backoff"
	"github.com/Rican7/retry/strategy"
	jsoniter "github.com/json-iterator/go"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"io"
	"net/http"
	"strconv"
	"time"
)

func refreshCookie(cookie Cookie) (Cookie, error) {
	if cookie.ExpireIn-time.Now().Unix() > 120 { // 2 分钟内过期时刷新
		return cookie, nil
	}

	return Login(GetConf().DouNaiURL, GetConf().Email, GetConf().Password)
}

func checkin(cookie Cookie) (msg string, err error) {
	var (
		surl = fmt.Sprintf("%s/user/checkin", GetConf().DouNaiURL)
		ret  Resp
	)

	newReq, err := http.NewRequest(http.MethodPost, surl, nil)
	if err != nil {
		err = errors.Wrapf(err, "checkin NewRequest error:%s", surl)
		logrus.Error(err.Error())
		return "", err
	}

	newReq.AddCookie(&http.Cookie{Name: "uid", Value: cookie.UID})
	newReq.AddCookie(&http.Cookie{Name: "ip", Value: cookie.IP})
	newReq.AddCookie(&http.Cookie{Name: "key", Value: cookie.Key})
	newReq.AddCookie(&http.Cookie{Name: "email", Value: cookie.Email})
	newReq.AddCookie(&http.Cookie{Name: "expire_in", Value: strconv.FormatInt(cookie.ExpireIn, 10)})

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	newReq = newReq.WithContext(ctx)

	// 忽略对证书的校验
	tr := &http.Transport{
		DisableKeepAlives: true,
		TLSClientConfig:   &tls.Config{InsecureSkipVerify: true}, //nolint:gosec // 目标服务可能使用无法验证的证书
	}

	newResp, err := (&http.Client{
		Transport: tr,
	}).Do(newReq)
	if err != nil {
		err = errors.Wrapf(err, "checkin request error:%s", surl)
		logrus.Error(err.Error())
		return "", err
	}
	defer newResp.Body.Close()
	if newResp.StatusCode < http.StatusOK || newResp.StatusCode >= http.StatusMultipleChoices {
		return "", fmt.Errorf("checkin request returned HTTP %s", newResp.Status)
	}

	newBody, err := io.ReadAll(newResp.Body)
	if err != nil {
		err = errors.Wrapf(err, "checkin io.ReadAll err")
		logrus.Error(err.Error())
		return "", err
	}

	err = jsoniter.Unmarshal(newBody, &ret)
	if err != nil {
		err = errors.Wrapf(err, "checkin Unmarshal ret err")
		logrus.Error(err.Error())
		return "", err
	}
	if ret.Ret != SuccessRetCode {
		return ret.Msg, fmt.Errorf("checkin failed: ret=%d, msg=%s", ret.Ret, ret.Msg)
	}

	return ret.Msg, nil
}

func ContinueLife(exit chan struct{}, cookie Cookie) {
	var (
		err             error
		msg             string
		lastCheckInDate string
	)
	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case t := <-ticker.C:
			nowTime := t.Format("15:04")
			today := t.Format("2006-01-02")

			// 1. 判断 cookie 是否过期或快要过期,如果是则重新登陆
			cookie, err = refreshCookie(cookie)
			if err != nil {
				err = errors.Wrapf(err, "ContinueLife refreshCookie err")
				logrus.Error(err.Error())
				_ = notifyCheckInResult(false, err.Error())
				close(exit)
				return
			}
			// 按 UTC+8 的配置时间每天自动签到
			if nowTime == GetConf().CheckInTime && lastCheckInDate != today {
				lastCheckInDate = today
				msg, err = tryCheckin(cookie)
				go func(msg string, err error) {
					if err != nil {
						_ = notifyCheckInResult(false, err.Error())
						return
					}
					_ = notifyCheckInResult(true, msg)
				}(msg, err)
			}
		}
	}
}

func tryCheckin(cookie Cookie) (msg string, err error) {
	action := func(attempt uint) (err error) {
		msg, err = checkin(cookie)
		if err != nil {
			logrus.Errorf("tryCheckin: %s", err.Error())
		}
		return err
	}
	err = retry.Retry(
		action,
		strategy.Limit(3),
		strategy.Backoff(backoff.Fibonacci(8*time.Second)),
	)

	return msg, err
}

func authenticate(email, password string) (Cookie, error) {
	dounaiURL := GetConf().DouNaiURL
	if dounaiURL == "" {
		return Cookie{}, fmt.Errorf("dounai_url is required")
	}

	cookie, err := Login(dounaiURL, email, password)
	if err != nil {
		return Cookie{}, err
	}

	SetEmail(email)
	SetPassword(password)
	return cookie, nil
}

// CheckInOnce logs in, checks in with retries, and returns. It is intended for
// external schedulers such as GitHub Actions and cron.
func CheckInOnce(email, password string) (string, error) {
	cookie, err := authenticate(email, password)
	if err != nil {
		return "", err
	}
	return tryCheckin(cookie)
}

func AutoCheckIn(email, password string) (err error) {
	var (
		exit = make(chan struct{})
	)

	cookie, err := authenticate(email, password)
	if err != nil {
		return err
	}

	logrus.Infof("dounai url: %s, check-in time: %s (UTC+8), email notification enabled: %t", GetConf().DouNaiURL, GetConf().CheckInTime, GetConf().EmailHost != "")
	// 定时去签到
	go ContinueLife(exit, cookie)

	<-exit
	return nil
}
