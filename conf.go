package main

type Conf struct {
	Debug         bool   `json:"debug"`           // 调试模式
	DouNaiURL     string `json:"dounai_url"`      // 豆奶网址的 url,比如 https://example.com
	Email         string `json:"username"`        // 用户名
	Password      string `json:"password"`        // 登录密码
	EmailAuthCode string `json:"email_auth_code"` // 邮箱授权码
	EmailHost     string `json:"email_host"`
	EmailPort     int    `json:"email_port"` //
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

func SetEmailPort(emailPort int) {
	conf.EmailPort = emailPort
}

func SetEmailHost(emailHost string) {
	conf.EmailHost = emailHost
}

func SetPassword(password string) {
	conf.Password = password
}

func GetConf() *Conf {
	return conf
}
