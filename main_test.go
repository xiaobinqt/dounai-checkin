package main

import "testing"

func Test_RefreshDomainURL(t *testing.T) {
	x, e := refreshDomainURL()
	t.Log(x, e)
}
