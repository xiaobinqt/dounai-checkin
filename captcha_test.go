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
		"玖-伍=":  "4",
		"陆乘柒=":  "42",
		"6÷陆=":  "1",
		"６／叁＝":  "2",
		"柒✕八=":  "56",
		"玖－四？":  "5",
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

func TestExtractSVGCaptchaText(t *testing.T) {
	markup := `<svg xmlns="http://www.w3.org/2000/svg"><circle/><text>玖</text><text>-</text><text>伍</text><text>=</text></svg>`
	got, isSVG, err := extractSVGCaptchaText(markup)
	if err != nil {
		t.Fatal(err)
	}
	if !isSVG || got != "玖-伍=" {
		t.Fatalf("extractSVGCaptchaText() = %q, %v; want 玖-伍=, true", got, isSVG)
	}
}

func TestSolveCaptchaRejectsUnsafeInput(t *testing.T) {
	for _, input := range []string{"", "1+2+3", "1/0", "7/2", "os.Exit(1)"} {
		if _, err := solveCaptcha(input); err == nil {
			t.Errorf("solveCaptcha(%q) error = nil", input)
		}
	}
}
