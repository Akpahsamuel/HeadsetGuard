CC = clang
CFLAGS = -Wall -Wextra -O2 -fobjc-arc -mmacosx-version-min=11.0 -Isrc
FRAMEWORKS = -framework Cocoa \
             -framework CoreAudio \
             -framework IOBluetooth \
             -framework LocalAuthentication \
             -framework Security \
             -framework QuartzCore

SRCS = src/main.m \
       src/AppDelegate.m \
       src/AudioGuard.m \
       src/BluetoothManager.m \
       src/SecurityManager.m \
       src/UnlockWindowController.m \
       src/PreferencesWindowController.m

APP_NAME = HeadsetGuard
APP_BUNDLE = build/$(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
APP_MACOS = $(APP_CONTENTS)/MacOS
APP_RESOURCES = $(APP_CONTENTS)/Resources

.PHONY: all build cli clean run test status

all: build

build: $(APP_MACOS)/$(APP_NAME)
	@echo "==> Packaging $(APP_NAME).app bundle..."
	@mkdir -p $(APP_CONTENTS) $(APP_MACOS) $(APP_RESOURCES)
	@cp resources/Info.plist $(APP_CONTENTS)/Info.plist
	@if [ -f resources/AppIcon.icns ]; then cp resources/AppIcon.icns $(APP_RESOURCES)/AppIcon.icns; fi
	@chmod +x $(APP_MACOS)/$(APP_NAME)
	@echo "==> Build successful: $(APP_BUNDLE)"

install: build
	@echo "==> Installing $(APP_NAME) to /Applications..."
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "==> Installed to /Applications/$(APP_NAME).app"

$(APP_MACOS)/$(APP_NAME): $(SRCS)
	@mkdir -p $(APP_MACOS)
	@echo "==> Compiling $(APP_NAME) binary..."
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(SRCS) -o $(APP_MACOS)/$(APP_NAME)

cli: build
	@mkdir -p bin
	@ln -sf ../$(APP_MACOS)/$(APP_NAME) bin/headsetguard
	@echo "==> CLI symlink created at bin/headsetguard"

run: build
	@echo "==> Launching $(APP_NAME)..."
	open $(APP_BUNDLE)

status: build
	@$(APP_MACOS)/$(APP_NAME) --status

list: build
	@$(APP_MACOS)/$(APP_NAME) --list

logs: build
	@$(APP_MACOS)/$(APP_NAME) --logs

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build bin
