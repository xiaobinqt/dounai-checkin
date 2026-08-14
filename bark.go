package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const defaultBarkServer = "https://api.day.app"

type barkRequest struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	Group string `json:"group"`
}

type barkResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func SendBark(title, body string) error {
	key := strings.TrimSpace(GetConf().BarkKey)
	if key == "" {
		return nil
	}

	server := strings.TrimRight(strings.TrimSpace(GetConf().BarkServer), "/")
	if server == "" {
		server = defaultBarkServer
	}
	parsedServer, err := url.ParseRequestURI(server)
	if err != nil || (parsedServer.Scheme != "https" && parsedServer.Scheme != "http") || parsedServer.Host == "" {
		return fmt.Errorf("invalid bark_server")
	}

	payload, err := json.Marshal(barkRequest{
		Title: title,
		Body:  body,
		Group: "豆奶签到",
	})
	if err != nil {
		return fmt.Errorf("marshal Bark request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		server+"/"+url.PathEscape(key),
		bytes.NewReader(payload),
	)
	if err != nil {
		return fmt.Errorf("create Bark request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json; charset=utf-8")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		if urlErr, ok := err.(*url.Error); ok {
			return fmt.Errorf("send Bark notification: %v", urlErr.Err)
		}
		return fmt.Errorf("send Bark notification: %w", err)
	}
	defer resp.Body.Close()

	responseBody, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("read Bark response: %w", err)
	}
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("Bark returned HTTP %s", resp.Status)
	}

	var result barkResponse
	if err := json.Unmarshal(responseBody, &result); err != nil {
		return fmt.Errorf("decode Bark response: %w", err)
	}
	if result.Code != http.StatusOK {
		return fmt.Errorf("Bark rejected notification: code=%d message=%s", result.Code, result.Message)
	}
	return nil
}
