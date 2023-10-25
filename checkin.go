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
	"io/ioutil"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

func refreshCookie(cookie Cookie) (Cookie, error) {
	if cookie.ExpireIn-time.Now().Unix() > 120 { // 2 个小时就要过期了去刷新
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
		TLSClientConfig:   &tls.Config{InsecureSkipVerify: true},
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

	return ret.Msg, nil
}

func ContinueLife(exit chan struct{}, cookie Cookie) {
	var (
		err error
		msg string
	)

	for {
		select {
		case t := <-time.After(1 * time.Minute):
			nowTime := t.Format("15:04")

			// 1. 判断 cookie 是否过期或快要过期,如果是则重新登陆
			cookie, err = refreshCookie(cookie)
			if err != nil {
				err = errors.Wrapf(err, "ContinueLife refreshCookie err")
				logrus.Error(err.Error())
				_ = SendEmail(msg)
				close(exit)
				return
			}
			// 每天 10 点自动签到
			if nowTime == "10:00" {
				msg, err = tryCheckin(cookie)
				go func(msg string, err error) {
					if err != nil {
						_ = SendEmail(err.Error())
						return
					}
					_ = SendEmail(msg)
				}(msg, err)
			}

			// 每天凌晨 2 点刷新 host url
			if nowTime == "02:10" {
				dounaiURL, err := refreshDomainURL()
				if err == nil {
					SetDouNaiUrl(dounaiURL)
				}
				logrus.Errorf("refreshDomainURL func err: %s", err.Error())
			}
		}
	}
}

func refreshDomainURL() (newURL string, err error) {
	doubledouURL := "https://doubledou.win/"
	newResp, err := http.Get(doubledouURL)
	if err != nil {
		err = errors.Wrapf(err, "refreshDomainURL err")
		logrus.Error(err.Error())
		return "", err
	}

	defer newResp.Body.Close()

	newBody, err := ioutil.ReadAll(newResp.Body)
	if err != nil {
		err = errors.Wrapf(err, "refreshDomainURL readall err")
		logrus.Error(err.Error())
		return "", err
	}

	re := regexp.MustCompile(`<h1>(.*?)</h1>`)
	htmlStr := string(newBody)
	match := re.FindStringSubmatch(htmlStr)

	if len(match) >= 2 {
		h1Content := match[1]
		h1Content = strings.ReplaceAll(h1Content, "新地址", "")
		return fmt.Sprintf("https://%s", h1Content), nil
	}

	err = fmt.Errorf("refreshDomainURL FindStringSubmatch err")
	logrus.Error(err.Error())
	return "", err
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

func AutoCheckIn(dounaiURL, eamil, password string) (err error) {
	var (
		exit = make(chan struct{})
	)

	// 先尝试登录
	cookie, err := Login(dounaiURL, eamil, password)
	if err != nil {
		return err
	}

	SetDouNaiUrl(dounaiURL)
	SetEmail(eamil)
	SetPassword(password)

	logrus.Infof("config: %+v", GetConf())
	// 定时去签到
	go ContinueLife(exit, cookie)

	<-exit
	return nil
}
