package main

import (
	"fmt"
	"strings"
	"time"
)

var shanghaiTimeZone = time.FixedZone("Asia/Shanghai", 8*60*60)

func notifyCheckInResult(success bool, message string) error {
	return notifyWithTitle(checkInNotificationTitle(success, message), message)
}

func checkInNotificationTitle(success bool, message string) string {
	title := "❌ 豆奶签到失败"
	if success {
		title = "✅ 豆奶签到成功"
		if isAlreadyCheckedInMessage(message) {
			title = "☑️ 豆奶今日已签到"
		}
	}
	return title
}

func checkInFailureMessage(message string, err error) string {
	if message = strings.TrimSpace(message); message != "" {
		return message
	}
	if err != nil {
		return err.Error()
	}
	return "签到失败，服务端未返回原因"
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
