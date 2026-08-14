package main

type Conf struct {
	Debug         bool   `json:"debug"`           // 调试模式
	DouNaiURL     string `json:"dounai_url"`      // 豆奶网址的 url,比如 https://example.com
	Email         string `json:"username"`        // 用户名
	EmailAuthCode string `json:"email_auth_code"` // 邮箱授权码
	EmailHost     string `json:"email_host"`
	EmailPort     int    `json:"email_port"` //
	EmailTLS      bool   `json:"email_tls"`
	CheckInTime   string `json:"checkin_time"`
	BarkKey       string `json:"bark_key"`
	BarkServer    string `json:"bark_server"`
}

var conf *Conf

func init() {
	conf = &Conf{}
}

func SetDebug(debug bool) {
	conf.Debug = debug
}

func SetDouNaiUrl(url string) {
	conf.DouNaiURL = url
}

func SetEmail(email string) {
	conf.Email = email
}

func SetEmailAuthCode(emailAuthCode string) {
	conf.EmailAuthCode = emailAuthCode
}

func SetEmailTLS(emailTLS bool) {
	conf.EmailTLS = emailTLS
}

func SetEmailPort(emailPort int) {
	conf.EmailPort = emailPort
}

func SetEmailHost(emailHost string) {
	conf.EmailHost = emailHost
}

func SetCheckInTime(checkInTime string) {
	conf.CheckInTime = checkInTime
}

func SetBarkKey(barkKey string) {
	conf.BarkKey = barkKey
}

func SetBarkServer(barkServer string) {
	conf.BarkServer = barkServer
}

func GetConf() *Conf {
	return conf
}
