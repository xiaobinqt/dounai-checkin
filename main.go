package main

import (
	"flag"
	"fmt"
	"github.com/json-iterator/go/extra"
	"github.com/sirupsen/logrus"
	"github.com/urfave/cli/v2"
	"log"
	"os"
	"time"
)

func main() {
	extra.RegisterFuzzyDecoders()
	flag.Parse()
	time.LoadLocation("Asia/Shanghai")

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
			},
			Usage: "start auto checkin",
			Action: func(c *cli.Context) error {
				email, password := c.String("email"), c.String("password")
				if email == "" || password == "" {
					log.Fatalf("params is invalid,email:[%s],password:[%s]", email, password)
				}
				SetEmailHost(c.String("email_host"))
				SetEmailPort(c.Int("email_port"))
				SetEmailAuthCode(c.String("email_auth_code"))
				SetEmailTLS(c.Bool("email_tls"))
				err := AutoCheckIn(email, password)
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
				logrus.Infof("config: %+v", GetConf())
				err := SendEmail("测试邮件服务")
				if err != nil {
					log.Fatalf("test send email err: %s", err.Error())
				}
				return nil
			},
		},
		{
			Name:  "doubledou",
			Usage: "get refresh dounai url",
			Action: func(c *cli.Context) error {
				u, err := getDomainURL()
				if err != nil {
					err = fmt.Errorf("refresh dounai url err: %s \n", err.Error())
					return err
				}
				fmt.Println("refresh dounai success: ", u)
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
