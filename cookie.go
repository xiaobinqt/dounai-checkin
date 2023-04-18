package main

type Cookie struct {
	UID      string `json:"uid"`
	Email    string `json:"email"`
	Key      string `json:"key"`
	IP       string `json:"ip"`
	ExpireIn int64  `json:"expire_in"`
}
