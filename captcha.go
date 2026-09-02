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
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/yangbin1322/go-ddddocr/ddddocr"
)

var captchaDataRE = regexp.MustCompile(`(?i)data:image/[^;]+;base64,([A-Za-z0-9+/=]+)`)
var captchaCodeRE = regexp.MustCompile(`^[0-9]{4}$`)

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
	if !captchaCodeRE.MatchString(code) {
		return "", fmt.Errorf("captcha recognizer returned %q, want four digits", code)
	}
	return code, nil
}

var (
	captchaOCROnce sync.Once
	captchaOCR     *ddddocr.DdddOcr
	captchaOCRErr  error
	captchaOCRMu   sync.Mutex
)

func recognizeCaptcha(img image.Image) (string, error) {
	var input bytes.Buffer
	if err := png.Encode(&input, img); err != nil {
		return "", fmt.Errorf("encode captcha for OCR: %w", err)
	}
	captchaOCROnce.Do(func() {
		modelDir := strings.TrimSpace(os.Getenv("DOUNAI_OCR_MODEL_DIR"))
		if modelDir == "" {
			modelDir = "models"
		}
		runtimeLibrary := map[string]string{"linux": "libonnxruntime.so", "darwin": "libonnxruntime.dylib", "windows": "onnxruntime.dll"}[runtime.GOOS]
		ddddocr.SetOnnxRuntimePath(filepath.Join(modelDir, runtimeLibrary))
		opts := ddddocr.DefaultOptions()
		opts.ModelDir = modelDir
		captchaOCR, captchaOCRErr = ddddocr.New(opts)
		if captchaOCRErr == nil {
			captchaOCR.SetRanges(ddddocr.RangeDigit)
		}
	})
	if captchaOCRErr != nil {
		return "", fmt.Errorf("initialize captcha OCR: %w", captchaOCRErr)
	}
	captchaOCRMu.Lock()
	defer captchaOCRMu.Unlock()
	result, err := captchaOCR.ClassificationWithOptions(input.Bytes(), ddddocr.ClassificationOptions{})
	if err != nil {
		return "", fmt.Errorf("recognize captcha: %w", err)
	}
	return strings.TrimSpace(result), nil
}
