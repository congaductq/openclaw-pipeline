FROM golang:1.23-alpine AS builder

WORKDIR /build
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o pipeline-server .

FROM alpine:3.20

RUN apk add --no-cache \
    bash curl jq openssh-client \
    terraform make \
    aws-cli docker-cli

WORKDIR /app

COPY --from=builder /build/pipeline-server /app/pipeline-server

EXPOSE 4000

ENTRYPOINT ["/app/pipeline-server"]
