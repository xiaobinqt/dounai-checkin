package main

import (
	"context"
	"crypto/tls"
	"fmt"
	jsoniter "github.com/json-iterator/go"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func Login(dounaiURL, email, password string) (cookie Cookie, err error) {
	var (
		v         = url.Values{}
		timeBegin = time.Now()
		body      string
		newBody   = make([]byte, 0)
		ret       Resp
	)

	defer func() {
		logrus.Infof("url:%s, cost:%d ms, body:%s", dounaiURL, time.Since(timeBegin).Milliseconds(), body)
	}()

	loginURL := fmt.Sprintf("%s/auth/login", dounaiURL)
	v.Set("email", email)
	v.Set("passwd", password)
	body = v.Encode()

	newReq, err := http.NewRequest(http.MethodPost, loginURL, strings.NewReader(body))
	if err != nil {
		err = errors.Wrapf(err, "NewRequest error:%s", loginURL)
		return Cookie{}, err
	}
	newReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	newReq = newReq.WithContext(ctx)
	logrus.Tracef("newReq:%+v", newReq)

	// 忽略对证书的校验
	tr := &http.Transport{
		DisableKeepAlives: true,
		TLSClientConfig:   &tls.Config{InsecureSkipVerify: true},
	}

	newResp, err := (&http.Client{
		Transport: tr,
	}).Do(newReq)
	if err != nil {
		err = errors.Wrapf(err, "request error:%s", dounaiURL)
		logrus.Error(err.Error())
		return Cookie{}, err
	}
	defer newResp.Body.Close()

	// 判断下是否登录成功,
	newBody, err = io.ReadAll(newResp.Body)
	if err != nil {
		err = errors.Wrapf(err, "Login readAll err")
		logrus.Error(err.Error())
		return Cookie{}, err
	}

	err = jsoniter.Unmarshal(newBody, &ret)
	if err != nil {
		err = errors.Wrapf(err, "Login unmarshal ret err")
		logrus.Error(err.Error())
		return Cookie{}, err
	}
	if ret.Ret != SuccessRetCode {
		err = fmt.Errorf("%s return ret not 1 is %d", loginURL, ret.Ret)
		logrus.Error(err.Error())
		return Cookie{}, nil
	}

	// 循环 cookie
	for _, c := range newResp.Cookies() {
		arr := strings.Split(c.String(), ";")
		if len(arr) < 1 {
			continue
		}
		first := strings.Split(arr[0], "=")
		if len(first) < 1 {
			continue
		}
		if first[0] == "uid" {
			cookie.UID = first[1]
		}
		if first[0] == "key" {
			cookie.Key = first[1]
		}
		if first[0] == "email" {
			cookie.Email = first[1]
		}
		if first[0] == "ip" {
			cookie.IP = first[1]
		}
		if first[0] == "expire_in" {
			expireIn, err := strconv.ParseInt(first[1], 10, 64)
			if err != nil {
				err = errors.Wrapf(err, "login get cookie parse expire in err: %s", err.Error())
				logrus.Error(err.Error())
				return Cookie{}, err
			}
			cookie.ExpireIn = expireIn
		}
	}

	return cookie, nil
}
