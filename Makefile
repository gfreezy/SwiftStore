.PHONY: test test-all test-core test-macros test-sync test-change-tracker build clean

# Run all tests (continues on failure)
test: test-all

test-all:
	@echo "=== Running all tests ==="
	@$(MAKE) test-core || true
	@$(MAKE) test-macros || true
	@$(MAKE) test-sync || true
	@$(MAKE) test-change-tracker || true
	@echo "=== All tests completed ==="

# Run only stable tests (core + macros)
test-stable: test-core test-macros
	@echo "Stable tests completed!"

# Individual package tests
test-core:
	@echo ""
	@echo "=== SwiftStoreCore Tests ==="
	@cd SwiftStoreCore && swift test

test-macros:
	@echo ""
	@echo "=== SwiftStoreMacros Tests ==="
	@cd SwiftStoreMacros && swift test

test-sync:
	@echo ""
	@echo "=== SwiftStoreSync Tests ==="
	@cd SwiftStoreSync && swift test

test-change-tracker:
	@echo ""
	@echo "=== SwiftStoreChangeTracker Tests ==="
	@cd SwiftStoreChangeTracker && swift test

# Build all packages
build:
	@echo "Building all packages..."
	@cd SwiftStoreProtocols && swift build
	@cd SwiftStoreMacros && swift build
	@cd SwiftStoreCore && swift build
	@cd SwiftStoreChangeTracker && swift build
	@cd SwiftStoreSync && swift build
	@cd SwiftStoreConnectionQueue && swift build
	@echo "Build completed!"

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@cd SwiftStoreProtocols && swift package clean
	@cd SwiftStoreMacros && swift package clean
	@cd SwiftStoreCore && swift package clean
	@cd SwiftStoreChangeTracker && swift package clean
	@cd SwiftStoreSync && swift package clean
	@cd SwiftStoreConnectionQueue && swift package clean
	@rm -rf .build
	@echo "Clean completed!"

# Run tests in parallel (faster but output may be interleaved)
test-parallel:
	@echo "Running all tests in parallel..."
	@cd SwiftStoreCore && swift test &
	@cd SwiftStoreMacros && swift test &
	@cd SwiftStoreSync && swift test &
	@cd SwiftStoreChangeTracker && swift test &
	@wait
	@echo "All tests completed!"
