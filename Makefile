.PHONY: test test-all build clean

# Run all tests
test: test-all

test-all:
	@echo "=== Running all tests ==="
	swift test
	@echo "=== All tests completed ==="

# Run specific test target
test-core:
	@echo "=== SwiftStoreCore Tests ==="
	swift test --filter SwiftStoreTests

test-macros:
	@echo "=== SwiftStoreMacros Tests ==="
	swift test --filter SwiftStoreMacroTests

test-sync:
	@echo "=== SwiftStoreSync Tests ==="
	swift test --filter SwiftStoreSyncTests

test-change-tracker:
	@echo "=== SwiftStoreChangeTracker Tests ==="
	swift test --filter SwiftStoreChangeTrackerTests

# Build all
build:
	@echo "Building..."
	swift build
	@echo "Build completed!"

# Build release
release:
	@echo "Building release..."
	swift build -c release
	@echo "Release build completed!"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build
	@echo "Clean completed!"

# Run tests in parallel
test-parallel:
	@echo "Running all tests in parallel..."
	swift test --parallel
	@echo "All tests completed!"
