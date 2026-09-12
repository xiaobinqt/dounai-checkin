package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
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

const captchaAllRanges = "0123456789+-xX*/=×÷加减乘除零〇一二两三四五六七八九壹贰貳叁參肆伍陆柒捌玖"
const captchaOperandRanges = "0123456789零〇一二两三四五六七八九壹贰貳叁參肆伍陆柒捌玖"
const captchaOperatorRanges = "+-xX*/×÷加减乘除"

// CaptchaRecognizer is injectable so deployments can provide a specialised
// OCR implementation while keeping the HTTP flow testable.
type CaptchaRecognizer func(image.Image) (string, error)

// fetchCaptcha obtains and solves the image challenge used by check-in.
func (s *Session) fetchCaptcha(ctx context.Context, recognize CaptchaRecognizer) (string, error) {
	s.lastCaptchaRequestURL = ""
	s.lastCaptchaResponseBody = ""
	s.lastCaptchaRawText = ""
	s.lastCaptchaCode = ""
	s.lastCaptchaChallenge = ""
	s.lastCaptchaSaltMask = ""
	// jQuery's cache:false parameter is a decimal cache-buster. Keep the same
	// shape instead of using the previous Go-specific timestamp-random format.
	requestPath := "/auth/captcha?type=checkin&_=" + strconv.FormatInt(time.Now().UnixMilli(), 10)
	resp, _, err := s.do(ctx, http.MethodGet, requestPath)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.Request != nil && resp.Request.URL != nil {
		s.lastCaptchaRequestURL = resp.Request.URL.String()
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return "", fmt.Errorf("read captcha response: %w", err)
	}
	s.lastCaptchaResponseBody = string(body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", s.captchaResponseError(resp, body, 0, "")
	}
	var result struct {
		Ret       int    `json:"ret"`
		Msg       string `json:"msg"`
		SVG       string `json:"svg"`
		Challenge string `json:"challenge"`
		SaltMask  string `json:"salt_mask"`
		Seed      string `json:"seed"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode captcha response: %w; %v", err, s.captchaResponseError(resp, body, 0, ""))
	}
	if result.Ret != 1 || strings.TrimSpace(result.SVG) == "" {
		return "", s.captchaResponseError(resp, body, result.Ret, result.Msg)
	}
	s.lastCaptchaChallenge = strings.TrimSpace(result.Challenge)
	s.lastCaptchaSaltMask = strings.TrimSpace(result.SaltMask)
	if seed := strings.TrimSpace(result.Seed); seed != "" {
		s.checkInTokenSeed = seed
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
	s.lastCaptchaRawText = code
	code, err = solveCaptcha(code)
	if err != nil {
		return "", err
	}
	if !captchaAnswerRE.MatchString(code) {
		return "", fmt.Errorf("captcha answer %q is invalid", code)
	}
	s.lastCaptchaCode = code
	return code, nil
}

func (s *Session) captchaResponseError(resp *http.Response, body []byte, ret int, message string) error {
	cookieNames := make([]string, 0, len(s.cookies))
	for name := range s.cookies {
		cookieNames = append(cookieNames, name)
	}
	sort.Strings(cookieNames)
	summary := strings.Join(strings.Fields(strings.TrimSpace(string(body))), " ")
	runes := []rune(summary)
	if len(runes) > 512 {
		summary = string(runes[:512]) + "…"
	}
	requestURL := s.baseURL + "/auth/captcha?type=checkin"
	if resp.Request != nil && resp.Request.URL != nil {
		requestURL = resp.Request.URL.String()
	}
	return fmt.Errorf(
		"captcha endpoint rejected request: url=%s, status=%s, content_type=%q, ret=%d, msg=%q, cookie_names=%v, response=%q",
		requestURL, resp.Status, resp.Header.Get("Content-Type"), ret, strings.TrimSpace(message), cookieNames, summary,
	)
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
	})
	if captchaOCRErr != nil {
		return "", fmt.Errorf("initialize captcha OCR: %w", captchaOCRErr)
	}
	type candidate struct {
		raw, answer string
	}
	var candidates []candidate
	var rawResults []string
	addCandidate := func(raw string, err error) {
		if err != nil || strings.TrimSpace(raw) == "" {
			return
		}
		rawResults = append(rawResults, raw)
		answer, solveErr := solveCaptcha(raw)
		if solveErr == nil {
			candidates = append(candidates, candidate{raw: raw, answer: answer})
		}
	}

	variants := []image.Image{img, highContrastCaptcha(img, 90), highContrastCaptcha(img, 120)}
	for _, variant := range variants {
		addCandidate(classifyCaptchaImage(variant, captchaAllRanges))
		addCandidate(recognizeCaptchaSlots(variant))
	}

	answerCounts := make(map[string]int)
	for _, candidate := range candidates {
		answerCounts[candidate.answer]++
		if answerCounts[candidate.answer] >= 2 {
			return candidate.raw, nil
		}
	}
	// Four-digit legacy captchas do not use arithmetic slots. Preserve their
	// original whole-image behavior when the first result is structurally valid.
	if len(candidates) > 0 && legacyCaptchaCodeRE.MatchString(candidates[0].answer) {
		return candidates[0].raw, nil
	}
	return "", fmt.Errorf("captcha OCR results did not reach consensus: %q", rawResults)
}

func classifyCaptchaImage(img image.Image, ranges string) (string, error) {
	var input bytes.Buffer
	if err := png.Encode(&input, img); err != nil {
		return "", fmt.Errorf("encode captcha for OCR: %w", err)
	}
	captchaOCRMu.Lock()
	defer captchaOCRMu.Unlock()
	captchaOCR.SetRanges(ranges)
	result, err := captchaOCR.ClassificationWithOptions(input.Bytes(), ddddocr.ClassificationOptions{})
	if err != nil {
		return "", fmt.Errorf("recognize captcha: %w", err)
	}
	return strings.TrimSpace(result), nil
}

func recognizeCaptchaSlots(img image.Image) (string, error) {
	bounds := img.Bounds()
	width := bounds.Dx()
	if width < 4 || bounds.Dy() < 1 {
		return "", fmt.Errorf("captcha image is too small")
	}
	slots := []struct {
		start, end int
		ranges     string
	}{
		{4, 33, captchaOperandRanges},
		{36, 66, captchaOperatorRanges},
		{69, 103, captchaOperandRanges},
	}
	var expression strings.Builder
	for _, slot := range slots {
		x1 := bounds.Min.X + width*slot.start/140
		x2 := bounds.Min.X + width*slot.end/140
		cropBounds := image.Rect(0, 0, x2-x1, bounds.Dy())
		crop := image.NewRGBA(cropBounds)
		draw.Draw(crop, cropBounds, img, image.Point{X: x1, Y: bounds.Min.Y}, draw.Src)
		text, err := classifyCaptchaImage(crop, slot.ranges)
		if err != nil {
			return "", err
		}
		expression.WriteString(text)
	}
	return expression.String() + "=", nil
}

func highContrastCaptcha(img image.Image, threshold uint8) image.Image {
	bounds := img.Bounds()
	result := image.NewGray(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			brightest := max(uint8(r>>8), uint8(g>>8), uint8(b>>8))
			value := uint8(0)
			if brightest >= threshold {
				value = 255
			}
			result.SetGray(x-bounds.Min.X, y-bounds.Min.Y, color.Gray{Y: value})
		}
	}
	return result
}

func solveCaptcha(raw string) (string, error) {
	expression := strings.NewReplacer(
		" ", "", "　", "", "×", "*", "✕", "*", "✖", "*", "＊", "*", "x", "*", "X", "*", "乘", "*",
		"÷", "/", "／", "/", "除", "/", "＋", "+", "加", "+", "−", "-", "－", "-", "减", "-", "＝", "=", "?", "", "？", "",
		"零", "0", "〇", "0", "一", "1", "壹", "1", "二", "2", "两", "2", "贰", "2", "貳", "2",
		"三", "3", "叁", "3", "參", "3", "四", "4", "肆", "4", "五", "5", "伍", "5",
		"六", "6", "陆", "6", "七", "7", "柒", "7", "八", "8", "捌", "8",
		"九", "9", "玖", "9", "０", "0", "１", "1", "２", "2", "３", "3", "４", "4",
		"５", "5", "６", "6", "７", "7", "８", "8", "９", "9",
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
