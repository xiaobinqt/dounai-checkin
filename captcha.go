package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"encoding/xml"
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
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/yangbin1322/go-ddddocr/ddddocr"
)

var captchaDataRE = regexp.MustCompile(`(?i)data:image/[^;]+;base64,([A-Za-z0-9+/=]+)`)
var captchaAnswerRE = regexp.MustCompile(`^(?:[0-9]{4}|-?[0-9]{1,3})$`)
var captchaExpressionRE = regexp.MustCompile(`^([0-9]{1,2})([+\-*/])([0-9]{1,2})$`)
var legacyCaptchaCodeRE = regexp.MustCompile(`^[0-9]{4}$`)

// CaptchaRecognizer is injectable so deployments can provide a specialised
// OCR implementation while keeping the HTTP flow testable.
type CaptchaRecognizer func(image.Image) (string, error)

// fetchCaptcha obtains and solves the image challenge used by check-in.
func (s *Session) fetchCaptcha(ctx context.Context, recognize CaptchaRecognizer) (string, error) {
	var b [8]byte
	_, _ = rand.Read(b[:])
	query := url.Values{"type": {"checkin"}, "_": {fmt.Sprintf("%d-%x", time.Now().UnixNano(), b)}}
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
	code, isSVG, err := extractSVGCaptchaText(result.SVG)
	if err != nil {
		return "", err
	}
	if !isSVG {
		match := captchaDataRE.FindStringSubmatch(result.SVG)
		if len(match) != 2 {
			return "", fmt.Errorf("captcha response contains neither SVG text nor a PNG image")
		}
		pngData, decodeErr := base64.StdEncoding.DecodeString(match[1])
		if decodeErr != nil {
			return "", fmt.Errorf("decode captcha image: %w", decodeErr)
		}
		img, decodeErr := png.Decode(bytes.NewReader(pngData))
		if decodeErr != nil {
			return "", fmt.Errorf("decode captcha PNG: %w", decodeErr)
		}
		if recognize == nil {
			recognize = recognizeCaptcha
		}
		code, err = recognize(img)
		if err != nil {
			return "", err
		}
	}
	code, err = solveCaptcha(code)
	if err != nil {
		return "", err
	}
	if !captchaAnswerRE.MatchString(code) {
		return "", fmt.Errorf("captcha answer %q is invalid", code)
	}
	return code, nil
}

func extractSVGCaptchaText(markup string) (string, bool, error) {
	if !strings.Contains(strings.ToLower(markup), "<svg") {
		return "", false, nil
	}
	decoder := xml.NewDecoder(strings.NewReader(markup))
	var text strings.Builder
	inText := false
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", true, fmt.Errorf("decode captcha SVG: %w", err)
		}
		switch value := token.(type) {
		case xml.StartElement:
			inText = value.Name.Local == "text"
		case xml.EndElement:
			if value.Name.Local == "text" {
				inText = false
			}
		case xml.CharData:
			if inText {
				text.Write(value)
			}
		}
	}
	if text.Len() == 0 {
		return "", true, fmt.Errorf("captcha SVG does not contain text")
	}
	return text.String(), true, nil
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
			captchaOCR.SetRanges("0123456789+-xX*/=×÷")
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

func solveCaptcha(raw string) (string, error) {
	expression := strings.NewReplacer(
		" ", "", "×", "*", "x", "*", "X", "*", "乘", "*",
		"÷", "/", "除", "/", "加", "+", "减", "-", "?", "",
		"零", "0", "〇", "0", "一", "1", "壹", "1", "二", "2", "两", "2", "贰", "2",
		"三", "3", "叁", "3", "四", "4", "肆", "4", "五", "5", "伍", "5",
		"六", "6", "陆", "6", "七", "7", "柒", "7", "八", "8", "捌", "8",
		"九", "9", "玖", "9",
	).Replace(strings.TrimSpace(raw))
	expression = strings.TrimSuffix(expression, "=")
	if legacyCaptchaCodeRE.MatchString(expression) {
		return expression, nil
	}
	match := captchaExpressionRE.FindStringSubmatch(expression)
	if len(match) != 4 {
		return "", fmt.Errorf("captcha recognizer returned %q, want four digits or a simple arithmetic expression", raw)
	}
	left, _ := strconv.Atoi(match[1])
	right, _ := strconv.Atoi(match[3])
	var answer int
	switch match[2] {
	case "+":
		answer = left + right
	case "-":
		answer = left - right
	case "*":
		answer = left * right
	case "/":
		if right == 0 || left%right != 0 {
			return "", fmt.Errorf("captcha expression %q does not have an integer result", raw)
		}
		answer = left / right
	}
	return strconv.Itoa(answer), nil
}
