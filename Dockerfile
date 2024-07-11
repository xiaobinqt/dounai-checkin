FROM golang:1.18 as build

COPY . /go/src/checkin

RUN  go env -w GO111MODULE=auto && \
     go env -w GOPROXY=https://goproxy.cn,direct && \
     cd /go/src/checkin && \
     go build -ldflags "-w -s -extldflags '-static'" -v -o dounai


FROM debian:sid-slim

RUN apt update && \
    apt-get install -y ca-certificates

ENV TZ=Asia/Shanghai

ENV PASSWORD=""
ENV EMAIL=""
ENV EMAIL_HOST=""
ENV EMAIL_PORT=""
ENV EMAIL_AUTH_CODE=""
ENV EMAIL_TLS=false

COPY --from=build /go/src/checkin/dounai /usr/bin/
COPY ./start.sh /scripts/

RUN chmod +x /scripts/start.sh

ENTRYPOINT ["/scripts/start.sh"]










