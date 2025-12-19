# Build stage
FROM golang:1.25 AS builder

WORKDIR /app

# Copy go.mod first for better layer caching
COPY go.mod ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
ENV CGO_ENABLED=0
ENV GOOS=linux
RUN go build -ldflags="-s -w" -o /app/main ./cmd/main.go

# Runtime stage
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/main .

# Run as non-root user
USER nonroot:nonroot

ENTRYPOINT ["/app/main"]
