package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var captchaDataRE = regexp.MustCompile(`(?i)data:image/[^;]+;base64,([A-Za-z0-9+/=]+)`)

// CaptchaRecognizer is injectable so deployments can provide a specialised
// OCR implementation while keeping the HTTP flow testable.
type CaptchaRecognizer func(image.Image) (string, error)

// fetchCaptcha obtains the same four-digit image used by the login page.
func (s *Session) fetchCaptcha(ctx context.Context, recognize CaptchaRecognizer) (string, error) {
	var b [8]byte
	_, _ = rand.Read(b[:])
	query := url.Values{"_": {fmt.Sprintf("%d-%x", time.Now().UnixNano(), b)}}
	resp, _, err := s.do(ctx, http.MethodGet, "/auth/captcha?"+query.Encode())
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", sessionHTTPError(resp)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return "", fmt.Errorf("read captcha response: %w", err)
	}
	var result struct {
		Ret int    `json:"ret"`
		SVG string `json:"svg"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode captcha response: %w", err)
	}
	if result.Ret != 1 || strings.TrimSpace(result.SVG) == "" {
		return "", fmt.Errorf("captcha endpoint returned ret=%d", result.Ret)
	}
	match := captchaDataRE.FindStringSubmatch(result.SVG)
	if len(match) != 2 {
		return "", fmt.Errorf("captcha response does not contain a PNG image")
	}
	pngData, err := base64.StdEncoding.DecodeString(match[1])
	if err != nil {
		return "", fmt.Errorf("decode captcha image: %w", err)
	}
	img, err := png.Decode(bytes.NewReader(pngData))
	if err != nil {
		return "", fmt.Errorf("decode captcha PNG: %w", err)
	}
	if recognize == nil {
		recognize = recognizeCaptcha
	}
	code, err := recognize(img)
	if err != nil {
		return "", err
	}
	code = strings.TrimSpace(code)
	if len(code) != 4 {
		return "", fmt.Errorf("captcha recognizer returned %q, want four digits", code)
	}
	return code, nil
}

var digitPatterns = [...]string{"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001", "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"}

// recognizeCaptcha is deliberately dependency-free. The site renders one
// coloured digit in each quarter of a fixed 160x54 image; downsampling each
// quarter to a 3x5 bitmap makes recognition tolerant of the crossing noise.
func recognizeCaptcha(img image.Image) (string, error) {
	b := img.Bounds()
	var out strings.Builder
	for pos := 0; pos < 4; pos++ {
		var best byte
		bestScore := int(^uint(0) >> 1)
		for d, pat := range digitPatterns {
			score := 0
			for y := 0; y < 5; y++ {
				for x := 0; x < 3; x++ {
					want := pat[(y*3+x)*1] == '1'
					px := b.Min.X + pos*b.Dx()/4 + (x+1)*b.Dx()/20
					py := b.Min.Y + (y+1)*b.Dy()/6
					c := img.At(px, py)
					r, g, bl, a := c.RGBA()
					on := a > 0x4000 && (r+g+bl)/3 > 0x5000
					if on != want {
						score++
					}
				}
			}
			if score < bestScore {
				bestScore, best = score, byte('0'+d)
			}
		}
		if best == 0 {
			return "", fmt.Errorf("captcha recognition failed")
		}
		out.WriteByte(best)
	}
	return out.String(), nil
}
