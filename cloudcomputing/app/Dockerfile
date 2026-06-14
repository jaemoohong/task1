# ---------------------------------------------------------------------------
# App Image (요구사항 7)
# - Go binary "book" (x86, TCP/8080 바인딩) 배포
# - 이미지 크기 8MB 이하로 경량화
# - 컨테이너 내부에 curl 사전 설치 (채점 시 curl 요청)
#
# 전략: scratch 기반 + 정적(static) curl + UPX 로 압축한 book 바이너리.
#   ./book        : 제공된 Go 바이너리를 이 디렉토리에 배치
# 빌드:
#   docker build --platform linux/amd64 -t wsc-repo:v1.0.0 .
# ---------------------------------------------------------------------------

# 1) book 바이너리 압축(UPX) + 정적 curl 준비
FROM alpine:3.20 AS builder
RUN apk add --no-cache upx curl-static ca-certificates || apk add --no-cache upx curl ca-certificates
WORKDIR /out
COPY book /out/book
# 8MB 제한을 맞추기 위해 실행 바이너리를 최대 압축
RUN upx --best --lzma /out/book || true
# 정적 curl 바이너리 확보 (curl-static 패키지 또는 시스템 curl)
RUN cp "$(command -v curl)" /out/curl

# 2) 최종 런타임 이미지 (scratch → 최소 용량)
FROM scratch
COPY --from=builder /out/book /book
COPY --from=builder /out/curl /usr/bin/curl
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
EXPOSE 8080
ENTRYPOINT ["/book"]
