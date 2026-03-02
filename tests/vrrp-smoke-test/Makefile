.PHONY: all test quick clean

all: quick

# Fast syntax check only
quick:
	@echo "Running quick config validation..."
	@./test-configs-only.sh

# Full test suite (requires keepalived)
test:
	@echo "Running full VRRP test suite..."
	@./test-vrrp-unshare.sh

# Clean up any leftover test files
clean:
	@rm -rf tmp/
	@echo "Cleaned up test files"

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@which unshare > /dev/null || (echo "ERROR: unshare not found" && exit 1)
	@which keepalived > /dev/null || (echo "ERROR: keepalived not found" && exit 1)
	@echo "All prerequisites met"
