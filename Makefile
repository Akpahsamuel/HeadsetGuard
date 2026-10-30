APP_NAME = HeadsetGuard
APP_BUNDLE = build/$(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
APP_MACOS = $(APP_CONTENTS)/MacOS
APP_RESOURCES = $(APP_CONTENTS)/Resources
SWIFT_BUILD_BIN = .build/release/$(APP_NAME)
TEST_FLAGS = -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays

.PHONY: all build cli clean run test status list logs install

all: build

build:
	@echo "==> Building $(APP_NAME) with SwiftPM..."
	@swift build -c release
	@mkdir -p $(APP_CONTENTS) $(APP_MACOS) $(APP_RESOURCES)
	@cp $(SWIFT_BUILD_BIN) $(APP_MACOS)/$(APP_NAME)
	@cp resources/Info.plist $(APP_CONTENTS)/Info.plist
	@if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(APP_RESOURCES)/AppIcon.icns; fi
	@chmod +x $(APP_MACOS)/$(APP_NAME)
	@echo "==> Build successful: $(APP_BUNDLE)"

test:
	@echo "==> Running tests..."
	@swift test $(TEST_FLAGS)

install: build
	@echo "==> Installing $(APP_NAME) to /Applications..."
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> Installed to /Applications/$(APP_NAME).app"

cli: build
	@mkdir -p bin
	@ln -sf ../$(APP_MACOS)/$(APP_NAME) bin/headsetguard
	@echo "==> CLI symlink created at bin/headsetguard"

run: build
	@echo "==> Launching $(APP_NAME)..."
	@open $(APP_BUNDLE)

status: build
	@$(APP_MACOS)/$(APP_NAME) --status

list: build
	@$(APP_MACOS)/$(APP_NAME) --list

logs: build
	@$(APP_MACOS)/$(APP_NAME) --logs

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build bin .build
