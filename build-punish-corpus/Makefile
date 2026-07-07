.PHONY: build test lint run
build:
	go build -o build-corpus ./cmd/build-corpus
test:
	go test ./...
run:
	go run ./cmd/build-corpus --config config.json
