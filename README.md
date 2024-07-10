# dounai-checkin

豆豆豆奶每天自动签到程序

## 前置条件

必须是豆豆豆奶/豆奶的用户，为了遵守豆奶网站公约，这里不会告诉你豆奶的网址以及豆奶是什么和怎么使用。

## 总览

<div align="center"><img src="https://cdn.xiaobinqt.cn/xiaobinqt.io/20230419/be92e64b88c4411a863954c1c7c8fae1.png?imageView2/0/q/75|watermark/2/text/eGlhb2JpbnF0/font/dmlqYXlh/fontsize/1000/fill/IzVDNUI1Qg==/dissolve/52/gravity/SouthEast/dx/15/dy/15" width=  /></div>

## 必填参数

+ password 登录密码
+ email 豆奶账号(邮箱)

## 编译运行

```shell
# 编译
go build -v -o dounai 

# 运行
./dounai start --password 登录密码 --email 豆奶账号(邮箱)
```

## 签到成功邮件通知

因为豆奶的账号就是用户邮箱，所以如果需要自动签到成功后进行邮件提醒，可以在启动时加上一些其他参数

+ email_host 邮箱服务器地址，比如 163 邮箱可以填写 smtp.163.com
+ email_port 邮箱服务端口
+ email_auth_code 邮箱授权密码

```shell
./dounai start \
--password 登录密码 \
--email 豆奶账号(邮箱)  \
--email_host 邮箱服务器地址 \
--email_port 邮箱服务端口 \
--email_auth_code 邮箱授权密码

# 以 163 邮箱示例
./dounai start \
--password 登录密码 \
--email 豆奶账号(邮箱) \
--email_host smtp.163.com \
--email_port 25 \
--email_auth_code 123456789X(邮箱授权码)
```

![](https://cdn.xiaobinqt.cn/xiaobinqt.io/20230419/8720861bdf004cd091e6e1a6e8291ff0.png?imageView2/0/q/75|watermark/2/text/eGlhb2JpbnF0/font/dmlqYXlh/fontsize/1000/fill/IzVDNUI1Qg==/dissolve/52/gravity/SouthEast/dx/15/dy/15)

## 测试邮箱连通性

```shell
./dounai test-email \
--email 豆奶账号(邮箱) \
--email_host 邮箱服务器地址 \
--email_port 邮箱服务端口 \
--email_auth_code 邮箱授权密码 [--email_tls true]
```

![](https://cdn.xiaobinqt.cn/xiaobinqt.io/20230419/081fd5d62c654133809cdb15e97ae7fc.png?imageView2/0/q/75|watermark/2/text/eGlhb2JpbnF0/font/dmlqYXlh/fontsize/1000/fill/IzVDNUI1Qg==/dissolve/52/gravity/SouthEast/dx/15/dy/15)

## 阿里云 ECS 25 端口发送邮件失败

出于安全考虑，阿里云默认封禁 TCP 25 端口出方向的访问流量。如果需要解封具体可以参考官方文档 [TCP 25端口解封申请](https://help.aliyun.com/document_detail/56130.html)。

这里可以使用 SSL 协议端口解决这个问题，在启动服务时加上一个参数

+ email_tls true

以 163 邮箱服务为例，这里的端口不是 25 非 SSL 端口了，改成了 465 SSL 端口。

```shell
./dounai start \
--password 登录密码 --email 豆奶账号(邮箱) \
--email_host smtp.163.com \
--email_port 465 \
--email_auth_code 123456789X(邮箱授权码) \
--email_tls true
```

## Docker 运行

可以看 dockerhub 说明 [xiaobinqt/checkin](https://hub.docker.com/r/xiaobinqt/dounai-checkin)

```shell
# 构建镜像
docker build -t dounai-checkin:v1 --progress=plain .

docker run -d --restart=always \ 
-e PASSWORD=登录密码 \
-e EMAIL=dustbin1234@163.com \
-e EMAIL_HOST=smtp.163.com \
-e EMAIL_PORT=465 \
-e EMAIL_AUTH_CODE=123456789X(邮箱授权码) \
-e EAMIL_TLS=true \
xiaobinqt/dounai-checkin:v1
```

