# chess openings — dev makefile
#
# wraps the usual xcodebuild invocations so they're short to type and
# easy to read. override PROJECT, SCHEME, or DESTINATION on the command
# line if you need a different target (e.g. a different simulator).

PROJECT     ?= Chess Openings.xcodeproj
SCHEME      ?= Chess Openings
DESTINATION ?= platform=iOS Simulator,name=iPhone 17

XCB = xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)"

.PHONY: build test test-all clean

# build only (no tests)
build:
	$(XCB) build

# run every test in the scheme
test-all:
	$(XCB) test

# run a subset of tests. usage:
#   make test T="Chess OpeningsTests/ChessCoreTests"
#   make test T="Chess OpeningsTests/ChessCoreTests/test_side_opposite"
# you can pass multiple by repeating the flag manually with ONLY, e.g.
#   make test ONLY='-only-testing:"A" -only-testing:"B"'
ONLY ?= $(if $(T),-only-testing:"$(T)",)
test:
	$(XCB) test $(ONLY)

clean:
	$(XCB) clean
