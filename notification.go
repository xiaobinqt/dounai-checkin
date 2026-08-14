package main

import (
	"fmt"
	"strings"
)

func notifyCheckInResult(success bool, message string) error {
	title := "❌ 豆奶签到失败"
	if success {
		title = "✅ 豆奶签到成功"
	}

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
