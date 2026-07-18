package main

import (
	"flag"
	"fmt"
	"github.com/json-iterator/go/extra"
	"github.com/sirupsen/logrus"
	"github.com/urfave/cli/v2"
	"log"
	"net/url"
	"os"
	"strings"
	"time"
)

func main() {
	extra.RegisterFuzzyDecoders()
	flag.Parse()
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		log.Fatalf("load timezone: %v", err)
	}
	time.Local = location

	app := cli.NewApp()
	app.Name = "dounai"
	app.Usage = "dounai auto checkin tool"
	app.Version = "1.0.0"

	// 多个命令，可以指定到 Commands 中
	app.Commands = []*cli.Command{
		{
			Name: "start",
			Flags: []cli.Flag{
				&cli.StringFlag{
					Name:    "email",
					Aliases: []string{"e"},
					Usage:   "dounai email",
				},
				&cli.StringFlag{
					Name:    "password",
					Aliases: []string{"p"},
					Usage:   "dounai password",
				},
				&cli.StringFlag{
					Name:  "email_host",
					Usage: "email host",
				},
				&cli.IntFlag{
					Name:  "email_port",
					Usage: "email server port",
				},
				&cli.BoolFlag{
					Name:  "email_tls",
					Usage: "email tls/是否使用 SSL 协议",
				},
				&cli.StringFlag{
					Name:  "email_auth_code",
					Usage: "email auth code/客户端授权码",
				},
				&cli.StringFlag{
					Name:  "checkin_time",
					Value: "10:00",
					Usage: "daily check-in time in UTC+8 (HH:MM)",
				},
				&cli.StringFlag{
					Name:  "dounai_url",
					Usage: "dounai URL, for example https://example.com",
				},
			},
			Usage: "start auto checkin",
			Action: func(c *cli.Context) error {
				email, password := c.String("email"), c.String("password")
				if email == "" || password == "" {
					return fmt.Errorf("email and password are required")
				}
				SetEmailHost(c.String("email_host"))
				SetEmailPort(c.Int("email_port"))
				SetEmailAuthCode(c.String("email_auth_code"))
				SetEmailTLS(c.Bool("email_tls"))
				checkInTime := c.String("checkin_time")
				if _, err := time.Parse("15:04", checkInTime); err != nil {
					return fmt.Errorf("invalid checkin_time %q, expected HH:MM", checkInTime)
				}
				SetCheckInTime(checkInTime)
				dounaiURL, err := normalizeDouNaiURL(c.String("dounai_url"))
				if err != nil {
					return err
				}
				SetDouNaiUrl(dounaiURL)
				err = AutoCheckIn(email, password)
				if err != nil {
					log.Fatalf("AutoCheckIn err: %s", err.Error())
				}
				return nil
			},
		},
		{
			Name:  "help",
			Usage: "dounai/dounai.exe start --username zs --password 123456",
			Action: func(c *cli.Context) error {
				fmt.Println("dounai/dounai.exe start -username zs -password 123456")
				return nil
			},
		},
		{
			Name:    "version",
			Aliases: []string{"v"},
			Usage:   "print the version",
			Action: func(c *cli.Context) error {
				fmt.Println(app.Version)
				return nil
			},
		},
		{
			Name:    "test-email",
			Aliases: []string{"te"},
			Usage:   "测试邮件",
			Flags: []cli.Flag{
				&cli.StringFlag{
					Name:    "email",
					Aliases: []string{"e"},
					Usage:   "dounai email",
				},
				&cli.StringFlag{
					Name:  "email_host",
					Usage: "email host",
				},
				&cli.BoolFlag{
					Name:  "email_tls",
					Usage: "email tls/是否使用 SSL 协议",
				},
				&cli.IntFlag{
					Name:  "email_port",
					Usage: "email server port",
				},
				&cli.StringFlag{
					Name:  "email_auth_code",
					Usage: "email auth code/客户端授权码",
				},
			},
			Action: func(c *cli.Context) error {
				SetEmail(c.String("email"))
				SetEmailHost(c.String("email_host"))
				SetEmailPort(c.Int("email_port"))
				SetEmailAuthCode(c.String("email_auth_code"))
				SetEmailTLS(c.Bool("email_tls"))
				logrus.Infof("email config: host=%s port=%d tls=%t", GetConf().EmailHost, GetConf().EmailPort, GetConf().EmailTLS)
				err := SendEmail("测试邮件服务")
				if err != nil {
					log.Fatalf("test send email err: %s", err.Error())
				}
				return nil
			},
		},
	}

	app.HideVersion = true
	//app.CustomAppHelpTemplate = "dounai -url https://example.com -username zs -password 123456"
	if err := app.Run(os.Args); err != nil {
		log.Fatalf("error: %v", err)
	}

}

func normalizeDouNaiURL(rawURL string) (string, error) {
	dounaiURL := strings.TrimRight(strings.TrimSpace(rawURL), "/")
	parsedURL, err := url.ParseRequestURI(dounaiURL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host == "" {
		return "", fmt.Errorf("invalid dounai_url %q, expected an https URL", rawURL)
	}
	return dounaiURL, nil
}
