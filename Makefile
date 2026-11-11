# Airspace — build with the Swift toolchain alone (Xcode not required).
APP_NAME   := Airspace
BUNDLE_ID  := com.airspace.wallpaper
VERSION    ?= 1.0.0
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
CONFIG     ?= release
INSTALL_DIR ?= /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Command Line Tools ship Swift Testing outside the default search paths.
DEV_DIR    := $(shell xcode-select -p)
TEST_FW    := $(firstword $(wildcard $(DEV_DIR)/Library/Developer/Frameworks $(DEV_DIR)/Platforms/MacOSX.platform/Developer/Library/Frameworks))
TEST_LIB   := $(firstword $(wildcard $(DEV_DIR)/Library/Developer/usr/lib $(DEV_DIR)/Platforms/MacOSX.platform/Developer/usr/lib))
TEST_FLAGS := $(if $(TEST_FW),-Xswiftc -F$(TEST_FW) -Xlinker -F$(TEST_FW) -Xlinker -rpath -Xlinker $(TEST_FW)) \
              $(if $(TEST_LIB),-Xlinker -rpath -Xlinker $(TEST_LIB))

SIGN_ID    ?= -
ENTITLEMENTS := Resources/Airspace.entitlements

.PHONY: build test app run install release dmg clean geodata snapshots icon

build:
	swift build -c $(CONFIG)

test:
	swift test $(TEST_FLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" $(APP)/Contents/MacOS/$(APP_NAME)
	sed -e 's/$$(VERSION)/$(VERSION)/g' -e 's/$$(BUNDLE_ID)/$(BUNDLE_ID)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	cp Resources/geodata.bin $(APP)/Contents/Resources/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/ 2>/dev/null || true
	codesign --force --options runtime --timestamp=none --entitlements $(ENTITLEMENTS) --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP)"

run: app
	open $(APP)

# Build, then replace the copy in /Applications and relaunch it. Quitting (rather than
# killing) lets Airspace restore your own system wallpaper before the new copy takes over.
install: app
	@if pgrep -x $(APP_NAME) >/dev/null; then \
	  echo "Quitting running $(APP_NAME)…"; \
	  osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true; \
	  for i in $$(seq 1 40); do pgrep -x $(APP_NAME) >/dev/null || break; sleep 0.25; done; \
	  if pgrep -x $(APP_NAME) >/dev/null; then echo "$(APP_NAME) didn't quit; close it and try again"; exit 1; fi; \
	fi
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto $(APP) "$(INSTALL_DIR)/$(APP_NAME).app"
	codesign --verify --deep --strict "$(INSTALL_DIR)/$(APP_NAME).app"
	$(LSREGISTER) -f "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed and launched $(INSTALL_DIR)/$(APP_NAME).app"

# Developer ID build + notarization:
#   make release SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=airspace
# where NOTARY_PROFILE was stored with `xcrun notarytool store-credentials`.
release: app
	@test "$(SIGN_ID)" != "-" || (echo "Set SIGN_ID to a Developer ID Application identity"; exit 1)
	codesign --force --options runtime --timestamp --entitlements $(ENTITLEMENTS) --sign "$(SIGN_ID)" $(APP)
	$(MAKE) dmg
	@if [ -n "$(NOTARY_PROFILE)" ]; then \
	  xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).dmg --keychain-profile "$(NOTARY_PROFILE)" --wait && \
	  xcrun stapler staple $(BUILD_DIR)/$(APP_NAME).dmg; \
	else echo "NOTARY_PROFILE not set; skipping notarization"; fi

dmg:
	rm -rf $(BUILD_DIR)/dmg $(BUILD_DIR)/$(APP_NAME).dmg
	mkdir -p $(BUILD_DIR)/dmg && cp -R $(APP) $(BUILD_DIR)/dmg/ && ln -s /Applications $(BUILD_DIR)/dmg/Applications
	hdiutil create -volname $(APP_NAME) -srcfolder $(BUILD_DIR)/dmg -ov -format UDZO $(BUILD_DIR)/$(APP_NAME).dmg

# Re-render Resources/AppIcon.icns from the AppIcon SwiftUI view.
icon:
	swift run -c $(CONFIG) $(APP_NAME) --icon $(BUILD_DIR)/AppIcon.iconset
	iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o Resources/AppIcon.icns

# Regenerate Resources/geodata.bin from public-domain sources.
geodata:
	./Tools/fetch_geodata.sh $(BUILD_DIR)/geo-src
	python3 -I Tools/build_geodata.py $(BUILD_DIR)/geo-src Resources/geodata.bin

# Render headless previews of every style/appearance into build/snapshots.
snapshots:
	swift run -c $(CONFIG) $(APP_NAME) --snapshots $(BUILD_DIR)/snapshots

clean:
	rm -rf .build $(BUILD_DIR)
