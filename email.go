package main

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
	"strings"

	"github.com/jordan-wright/email"
)

var (
	em *email.Email
)

// 这里暂时不会出现并发的情况
func getEmail() *email.Email {
	if em != nil {
		return em
	}
	return email.NewEmail()
}

// 自己发信给自己
func SendEmail(msg string) (err error) {
	if !emailNotificationConfigured() {
		return nil
	}
	if err := validateEmailNotificationConfig(); err != nil {
		return err
	}

	e := getEmail()
	//设置发送方的邮箱
	e.From = GetConf().Email
	// 设置接收方的邮箱
	e.To = []string{GetConf().Email}
	//设置主题
	e.Subject = "豆豆豆奶自动签到"
	//设置文件发送的内容
	e.Text = []byte(msg)
	//设置服务器相关的配置
	serverAddress := fmt.Sprintf("%s:%d", GetConf().EmailHost, GetConf().EmailPort)
	if GetConf().EmailTLS {
		err = e.SendWithTLS(serverAddress,
			smtp.PlainAuth("", GetConf().Email, GetConf().EmailAuthCode, GetConf().EmailHost), &tls.Config{
				InsecureSkipVerify: true, //nolint:gosec // 兼容无法验证证书的 SMTP 服务
				ServerName:         GetConf().EmailHost,
			})
	} else {
		err = e.Send(serverAddress,
			smtp.PlainAuth("", GetConf().Email, GetConf().EmailAuthCode, GetConf().EmailHost))
	}
	if err != nil {
		return fmt.Errorf("send email via %s (tls=%t): %w", serverAddress, GetConf().EmailTLS, err)
	}

	return nil
}

func emailNotificationConfigured() bool {
	conf := GetConf()
	return strings.TrimSpace(conf.Email) != "" ||
		strings.TrimSpace(conf.EmailHost) != "" ||
		conf.EmailPort != 0 ||
		strings.TrimSpace(conf.EmailAuthCode) != "" ||
		conf.EmailTLS
}

func validateEmailNotificationConfig() error {
	conf := GetConf()
	var missing []string
	if strings.TrimSpace(conf.Email) == "" {
		missing = append(missing, "EMAIL")
	}
	if strings.TrimSpace(conf.EmailHost) == "" {
		missing = append(missing, "EMAIL_HOST")
	}
	if conf.EmailPort == 0 {
		missing = append(missing, "EMAIL_PORT")
	}
	if strings.TrimSpace(conf.EmailAuthCode) == "" {
		missing = append(missing, "EMAIL_AUTH_CODE")
	}
	if len(missing) > 0 {
		return fmt.Errorf("incomplete email notification config: missing %s", strings.Join(missing, ", "))
	}
	return nil
}
