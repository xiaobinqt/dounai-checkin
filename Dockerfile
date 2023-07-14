FROM golang:1.18 as build

COPY . /go/src/checkin

RUN  go env -w GO111MODULE=auto && \
     go env -w GOPROXY=https://goproxy.cn,direct && \
     cd /go/src/checkin && \
     go build -ldflags "-w -s -extldflags '-static'" -v -o dounai


FROM debian:sid-slim

ENV TZ=Asia/Shanghai

ENV URL=""
ENV PASSWORD=""
ENV EAMIL=""
ENV EMAIL_HOST=""
ENV EMAIL_PORT=""
ENV EMAIL_AUTH_CODE=""
ENV EMAIL_TLS=false

COPY --from=build /go/src/checkin/dounai /usr/bin/
COPY ./start.sh /scripts/


ENTRYPOINT ["/scripts/start.sh"]










