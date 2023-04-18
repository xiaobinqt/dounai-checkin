package main

type Resp struct {
	Ret int    `json:"ret"` // 等于 1 时是成功
	Msg string `json:"msg"`
}

const SuccessRetCode = 1
