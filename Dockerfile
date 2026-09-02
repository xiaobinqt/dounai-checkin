FROM golang:1.25 AS build

COPY . /go/src/checkin

RUN  go env -w GO111MODULE=auto && \
     go env -w GOPROXY=https://goproxy.cn,direct && \
     cd /go/src/checkin && \
     go build -ldflags "-w -s -extldflags '-static'" -v -o dounai


FROM debian:bookworm-slim

RUN apt-get update && \
	apt-get install -y --no-install-recommends ca-certificates curl && \
	rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG TARGETARCH
RUN mkdir -p /app/models && \
	curl -fsSL -o /app/models/common_old.onnx https://github.com/yangbin1322/go-ddddocr/releases/download/v1.0.1/common_old.onnx && \
	curl -fsSL -o /app/models/charsets_old.json https://github.com/yangbin1322/go-ddddocr/releases/download/v1.0.1/charsets_old.json && \
	case "$TARGETARCH" in amd64) ort_arch=x64 ;; arm64) ort_arch=aarch64 ;; *) exit 1 ;; esac && \
	curl -fsSL "https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-linux-${ort_arch}-1.23.2.tgz" | \
	tar -xz -C /app/models --strip-components=2 "onnxruntime-linux-${ort_arch}-1.23.2/lib/libonnxruntime.so.1.23.2" && \
	mv /app/models/libonnxruntime.so.1.23.2 /app/models/libonnxruntime.so

ENV TZ=Asia/Shanghai
ENV DOUNAI_OCR_MODEL_DIR="/app/models"

ENV DOUNAI_COOKIE=""
ENV EMAIL=""
ENV EMAIL_HOST=""
ENV EMAIL_PORT=""
ENV EMAIL_AUTH_CODE=""
ENV EMAIL_TLS=false
ENV CHECKIN_TIME=10:00
ENV DOUNAI_URL=""
ENV BARK_KEY=""
ENV BARK_SERVER="https://api.day.app"

COPY --from=build /go/src/checkin/dounai /usr/bin/
COPY ./start.sh /scripts/

RUN chmod +x /scripts/start.sh

ENTRYPOINT ["/scripts/start.sh"]
