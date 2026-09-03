package main

import "testing"

func TestSolveCaptcha(t *testing.T) {
	tests := map[string]string{
		"6935":  "6935",
		"6×7=":  "42",
		"8 x 4": "32",
		"9+3=?": "12",
		"9-7=":  "2",
		"8÷2=":  "4",
	}
	for input, want := range tests {
		got, err := solveCaptcha(input)
		if err != nil {
			t.Errorf("solveCaptcha(%q): %v", input, err)
		} else if got != want {
			t.Errorf("solveCaptcha(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestSolveCaptchaRejectsUnsafeInput(t *testing.T) {
	for _, input := range []string{"", "1+2+3", "1/0", "7/2", "os.Exit(1)"} {
		if _, err := solveCaptcha(input); err == nil {
			t.Errorf("solveCaptcha(%q) error = nil", input)
		}
	}
}
