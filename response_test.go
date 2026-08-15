package main

import "testing"

func TestValidateCheckInResponse(t *testing.T) {
	tests := []struct {
		name    string
		result  Resp
		wantErr bool
	}{
		{
			name:   "reward granted",
			result: Resp{Ret: 1, Msg: "获得了 674 MB流量和1个豆丁，账号有效期及等级 1 时长延长 1.64 小时。"},
		},
		{
			name:   "already checked in",
			result: Resp{Ret: 1, Msg: "您今天已经续过命了。"},
		},
		{
			name:    "retry requested despite ret one",
			result:  Resp{Ret: 1, Msg: "请刷新页面后重试。"},
			wantErr: true,
		},
		{
			name:    "unknown ret one response",
			result:  Resp{Ret: 1, Msg: "操作已处理"},
			wantErr: true,
		},
		{
			name:    "explicit failure code",
			result:  Resp{Ret: 0, Msg: "签到失败"},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateCheckInResponse(tt.result)
			if (err != nil) != tt.wantErr {
				t.Fatalf("validateCheckInResponse(%+v) error = %v, wantErr %t", tt.result, err, tt.wantErr)
			}
		})
	}
}
