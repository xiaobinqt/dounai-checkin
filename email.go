package main

import (
	"fmt"
	"github.com/jordan-wright/email"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"net/smtp"
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
	if GetConf().EmailHost == "" || GetConf().EmailPort == 0 || GetConf().EmailAuthCode == "" {
		logrus.Warnf("邮件配置为空，暂不会通过邮件通知。")
		return nil
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
	err = e.Send(fmt.Sprintf("%s:%d", GetConf().EmailHost, GetConf().EmailPort),
		smtp.PlainAuth("", GetConf().Email, GetConf().EmailAuthCode, GetConf().EmailHost))
	if err != nil {
		err = errors.Wrapf(err, "豆豆豆奶自动签到程序发送邮件失败: %s", err.Error())
		logrus.Error(err.Error())
		return err
	}

	return nil
}
