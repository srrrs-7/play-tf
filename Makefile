.PHONY: build run clean help

# Variables
APP_NAME := app
IMAGE_TAG := latest
DOCKER_FILE := app/.image/Dockerfile
BUILD_CONTEXT := app/src

# Build Docker image
build:
	docker build -f $(DOCKER_FILE) -t $(APP_NAME):$(IMAGE_TAG) $(BUILD_CONTEXT)

# Run Docker container
run: build
	docker run --rm $(APP_NAME):$(IMAGE_TAG)

# Remove Docker image
clean:
	docker rmi $(APP_NAME):$(IMAGE_TAG) 2>/dev/null || true

# Show help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build   Build Docker image"
	@echo "  run     Build and run Docker container"
	@echo "  clean   Remove Docker image"
	@echo "  help    Show this help message"
