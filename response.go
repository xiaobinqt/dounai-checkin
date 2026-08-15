package main

import (
	"fmt"
	"regexp"
	"strings"
)

type Resp struct {
	Ret int    `json:"ret"` // 1 表示接口已处理请求，是否签到成功还需检查 Msg
	Msg string `json:"msg"`
}

const handledRetCode = 1

var checkInRewardMessagePattern = regexp.MustCompile(`(?:^|[^未])获得了?[[:space:]]*[0-9]`)

func validateCheckInResponse(result Resp) error {
	if result.Ret != handledRetCode {
		return fmt.Errorf("check-in failed: ret=%d, msg=%s", result.Ret, result.Msg)
	}
	if !isSuccessfulCheckInMessage(result.Msg) {
		return fmt.Errorf("check-in not confirmed: ret=%d, msg=%s", result.Ret, result.Msg)
	}
	return nil
}

// ret=1 only means that the endpoint handled the request. Dounai also uses it
// for messages such as "请刷新页面后重试。", which must not be reported as a
// successful check-in. Only explicit reward or already-checked-in messages are
// accepted here so unknown responses fail closed.
func isSuccessfulCheckInMessage(message string) bool {
	message = strings.TrimSpace(message)
	if message == "" {
		return false
	}
	if isAlreadyCheckedInMessage(message) {
		return true
	}
	if strings.Contains(message, "签到成功") || strings.Contains(message, "续命成功") {
		return true
	}
	return checkInRewardMessagePattern.MatchString(message)
}

func isAlreadyCheckedInMessage(message string) bool {
	for _, marker := range []string{"已经续过命", "已续过命", "已经签到", "已签到"} {
		if strings.Contains(message, marker) {
			return true
		}
	}
	return false
}
