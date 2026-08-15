package main

import (
	"strings"
	"testing"
)

func TestSendEmailSilentlySkipsWhenNotConfigured(t *testing.T) {
	originalConf := *GetConf()
	defer func() { *GetConf() = originalConf }()

	*GetConf() = Conf{}
	if err := SendEmail("test"); err != nil {
		t.Fatalf("SendEmail() error = %v", err)
	}
}

func TestSendEmailRejectsPartialConfiguration(t *testing.T) {
	originalConf := *GetConf()
	defer func() { *GetConf() = originalConf }()

	*GetConf() = Conf{Email: "user@example.com"}
	err := SendEmail("test")
	if err == nil {
		t.Fatal("SendEmail() error = nil, want incomplete-config error")
	}
	for _, name := range []string{"EMAIL_HOST", "EMAIL_PORT", "EMAIL_AUTH_CODE"} {
		if !strings.Contains(err.Error(), name) {
			t.Fatalf("SendEmail() error = %q, want missing %s", err, name)
		}
	}
}
