package main

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/json-iterator/go/extra"
	"github.com/sirupsen/logrus"
	"github.com/urfave/cli/v2"
)

func main() {
	extra.RegisterFuzzyDecoders()
	time.Local = time.FixedZone("Asia/Shanghai", 8*60*60)

	app := cli.NewApp()
	app.Name = "dounai"
	app.Usage = "dounai auto checkin tool"
	app.Version = "1.0.0"

	app.Commands = []*cli.Command{
		{
			Name:    "once",
			Aliases: []string{"checkin"},
			Usage:   "check in once and exit (recommended for GitHub Actions)",
			Flags:   checkInFlags(false),
			Action: func(c *cli.Context) error {
				email, password, err := configureCheckIn(c, false)
				if err != nil {
					if notifyErr := notifyCheckInResult(false, err.Error()); notifyErr != nil {
						logrus.Errorf("send configuration failure notification: %v", notifyErr)
					}
					return err
				}

				msg, err := CheckInOnce(email, password)
				if err != nil {
					if notifyErr := notifyCheckInResult(false, err.Error()); notifyErr != nil {
						logrus.Errorf("send failure notification: %v", notifyErr)
					}
					return err
				}
				logrus.Infof("check-in succeeded: %s", msg)
				return notifyCheckInResult(true, msg)
			},
		},
		{
			Name:  "start",
			Usage: "start the long-running daily scheduler",
			Flags: checkInFlags(true),
			Action: func(c *cli.Context) error {
				email, password, err := configureCheckIn(c, true)
				if err != nil {
					return err
				}
				return AutoCheckIn(email, password)
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
			Flags:   emailFlags(),
			Action: func(c *cli.Context) error {
				configureEmail(c)
				logrus.Infof("email config: host=%s port=%d tls=%t", GetConf().EmailHost, GetConf().EmailPort, GetConf().EmailTLS)
				return SendEmail("测试邮件服务")
			},
		},
	}

	app.HideVersion = true
	if err := app.Run(os.Args); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func checkInFlags(withSchedule bool) []cli.Flag {
	flags := []cli.Flag{
		&cli.StringFlag{
			Name:    "email",
			Aliases: []string{"e"},
			EnvVars: []string{"DOUNAI_EMAIL", "EMAIL"},
			Usage:   "dounai account email",
		},
		&cli.StringFlag{
			Name:    "password",
			Aliases: []string{"p"},
			EnvVars: []string{"DOUNAI_PASSWORD", "PASSWORD"},
			Usage:   "dounai account password",
		},
		&cli.StringFlag{
			Name:    "dounai_url",
			EnvVars: []string{"DOUNAI_URL"},
			Usage:   "dounai URL, for example https://example.com",
		},
	}
	flags = append(flags, emailFlags()[1:]...)
	flags = append(flags,
		&cli.StringFlag{
			Name:    "bark_key",
			EnvVars: []string{"BARK_KEY"},
			Usage:   "Bark device key",
		},
		&cli.StringFlag{
			Name:    "bark_server",
			EnvVars: []string{"BARK_SERVER"},
			Value:   defaultBarkServer,
			Usage:   "Bark server URL",
		},
	)
	if withSchedule {
		flags = append(flags, &cli.StringFlag{
			Name:    "checkin_time",
			EnvVars: []string{"CHECKIN_TIME"},
			Value:   "10:00",
			Usage:   "daily check-in time in UTC+8 (HH:MM)",
		})
	}
	return flags
}

func emailFlags() []cli.Flag {
	return []cli.Flag{
		&cli.StringFlag{
			Name:    "email",
			Aliases: []string{"e"},
			EnvVars: []string{"DOUNAI_EMAIL", "EMAIL"},
			Usage:   "sender and recipient email",
		},
		&cli.StringFlag{
			Name:    "email_host",
			EnvVars: []string{"EMAIL_HOST"},
			Usage:   "SMTP server host",
		},
		&cli.IntFlag{
			Name:    "email_port",
			EnvVars: []string{"EMAIL_PORT"},
			Usage:   "SMTP server port",
		},
		&cli.BoolFlag{
			Name:    "email_tls",
			EnvVars: []string{"EMAIL_TLS"},
			Usage:   "use SMTP TLS/SSL",
		},
		&cli.StringFlag{
			Name:    "email_auth_code",
			EnvVars: []string{"EMAIL_AUTH_CODE"},
			Usage:   "SMTP client authorization code",
		},
	}
}

func configureCheckIn(c *cli.Context, withSchedule bool) (string, string, error) {
	email := strings.TrimSpace(c.String("email"))
	password := c.String("password")
	configureEmail(c)
	SetBarkKey(strings.TrimSpace(c.String("bark_key")))
	SetBarkServer(strings.TrimRight(strings.TrimSpace(c.String("bark_server")), "/"))

	if email == "" || password == "" {
		return "", "", fmt.Errorf("email and password are required")
	}

	dounaiURL, err := normalizeDouNaiURL(c.String("dounai_url"))
	if err != nil {
		return "", "", err
	}
	SetDouNaiUrl(dounaiURL)

	if withSchedule {
		checkInTime := c.String("checkin_time")
		if _, err := time.Parse("15:04", checkInTime); err != nil {
			return "", "", fmt.Errorf("invalid checkin_time %q, expected HH:MM", checkInTime)
		}
		SetCheckInTime(checkInTime)
	}

	return email, password, nil
}

func configureEmail(c *cli.Context) {
	SetEmail(strings.TrimSpace(c.String("email")))
	SetEmailHost(c.String("email_host"))
	SetEmailPort(c.Int("email_port"))
	SetEmailAuthCode(c.String("email_auth_code"))
	SetEmailTLS(c.Bool("email_tls"))
}

func normalizeDouNaiURL(rawURL string) (string, error) {
	dounaiURL := strings.TrimRight(strings.TrimSpace(rawURL), "/")
	parsedURL, err := url.ParseRequestURI(dounaiURL)
	if err != nil || parsedURL.Scheme != "https" || parsedURL.Host == "" {
		return "", fmt.Errorf("invalid dounai_url %q, expected an https URL", rawURL)
	}
	return dounaiURL, nil
}
