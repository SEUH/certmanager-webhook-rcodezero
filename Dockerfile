# syntax=docker/dockerfile:1
FROM golang:1.25 AS builder

WORKDIR /workspace
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/webhook .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /out/webhook /usr/local/bin/webhook

USER 65532:65532
ENTRYPOINT ["/usr/local/bin/webhook"]
