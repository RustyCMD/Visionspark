.PHONY: help test test-watch test-coverage clean build-runner deps format lint

# Default target
help:
	@echo "VisionSpark Development Commands"
	@echo "================================"
	@echo "deps          - Install dependencies"
	@echo "build-runner  - Generate mock files"
	@echo "test          - Run all tests"
	@echo "test-watch    - Run tests in watch mode"
	@echo "test-coverage - Run tests with coverage"
	@echo "format        - Format code"
	@echo "lint          - Run linter"
	@echo "clean         - Clean build files"

# Install dependencies
deps:
	flutter pub get

# Generate mock files for testing
build-runner:
	flutter packages pub run build_runner build --delete-conflicting-outputs

# Run all tests
test:
	flutter test

# Run tests in watch mode
test-watch:
	flutter test --watch

# Run tests with coverage
test-coverage:
	flutter test --coverage
	@echo "Coverage report generated in coverage/lcov.info"
	@echo "To view in browser: genhtml coverage/lcov.info -o coverage/html && open coverage/html/index.html"

# Format code
format:
	dart format .

# Run linter
lint:
	flutter analyze

# Clean build files
clean:
	flutter clean
	rm -rf .dart_tool
	rm -rf coverage
	rm -rf build

# Setup development environment
setup: deps build-runner
	@echo "Development environment setup complete!"
	@echo "Run 'make test' to run the test suite"

# Quick development cycle
dev: format lint test
	@echo "Development cycle complete!"

# CI/CD pipeline
ci: deps build-runner lint test
	@echo "CI pipeline complete!"