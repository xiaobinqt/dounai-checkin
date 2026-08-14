package main

import (
	"fmt"
	"strings"
	"time"
)

var shanghaiTimeZone = time.FixedZone("Asia/Shanghai", 8*60*60)

func notifyCheckInResult(success bool, message string) error {
	title := "❌ 豆奶签到失败"
	if success {
		title = "✅ 豆奶签到成功"
	}
	return notifyWithTitle(title, message)
}

func notifySessionFailure(message string) error {
	if !shouldNotifySessionFailure(time.Now()) {
		return nil
	}
	return notifyWithTitle("⚠️ 豆奶登录态失效", message)
}

func shouldNotifySessionFailure(now time.Time) bool {
	hour := now.In(shanghaiTimeZone).Hour()
	return hour >= 9
}

func notifyWithTitle(title, message string) error {
	var notificationErrors []string
	if err := SendBark(title, message); err != nil {
		notificationErrors = append(notificationErrors, err.Error())
	}
	if err := SendEmail(message); err != nil {
		notificationErrors = append(notificationErrors, err.Error())
	}
	if len(notificationErrors) > 0 {
		return fmt.Errorf("send notification: %s", strings.Join(notificationErrors, "; "))
	}
	return nil
}
