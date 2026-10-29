SHELL := /bin/zsh
export PATH := /opt/homebrew/bin:$(PATH)

-include Local.xcconfig

PROJECT := VelovCompagnon.xcodeproj
SCHEME := VelovCompagnon
DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData/VelovCompagnon-make
DEVICE := $(VELOV_DEVICE)
SIM_NAME := Velov iPhone 17 Pro
SIM_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
APP_DEVICE := $(DERIVED)/Build/Products/Debug-iphoneos/VelovCompagnon.app
LOG := $(DERIVED)/logs

.PHONY: project assets build build-unsigned build-sim test smoke install snapshots clean local-config

assets:
	python3 scripts/fetch-assets.py
	test -f App/Resources/Fonts/VelovGlyphic-Regular.ttf -a -f App/Resources/Fonts/VelovGlyphicTimer-Regular.ttf || python3 scripts/make-number-font.py
	test -f App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png || swift scripts/make-icon.swift

project: assets
	/opt/homebrew/bin/xcodegen generate --quiet

local-config:
	@test -f Local.xcconfig || { echo "Local.xcconfig manquant : copiez Local.example.xcconfig et renseignez DEVELOPMENT_TEAM et VELOV_DEVICE."; exit 1; }
	@test -n "$(DEVICE)" || { echo "VELOV_DEVICE manquant dans Local.xcconfig."; exit 1; }

build: local-config project
	mkdir -p $(LOG)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'id=$(DEVICE)' \
	  -derivedDataPath $(DERIVED) -allowProvisioningUpdates build 2>&1 | tee $(LOG)/build.log | grep -E "error:|warning:|BUILD" ; \
	  exit $${pipestatus[1]}

build-unsigned: project
	mkdir -p $(LOG)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'generic/platform=iOS' \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build 2>&1 | tee $(LOG)/build-unsigned.log | grep -E "error:|warning:|BUILD" ; \
	  exit $${pipestatus[1]}

build-sim: project
	mkdir -p $(LOG)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'generic/platform=iOS Simulator' \
	  -derivedDataPath $(DERIVED) build 2>&1 | tee $(LOG)/build-sim.log | grep -E "error:|warning:|BUILD" ; \
	  exit $${pipestatus[1]}

test:
	cd Packages/VelovCore && swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -5 ; exit $${pipestatus[1]}

smoke:
	cd Packages/VelovCore && VELOV_LIVE=1 swift test --filter LiveSmokeTests 2>&1 | grep -E "LIVE|error|Executed" ; exit $${pipestatus[1]}

install: local-config
	xcrun devicectl device install app --device $(DEVICE) $(APP_DEVICE)

snapshots: build-sim
	SIM_NAME="$(SIM_NAME)" SIM_TYPE="$(SIM_TYPE)" DERIVED="$(DERIVED)" zsh scripts/snapshots.sh

clean:
	rm -rf $(DERIVED) $(PROJECT)
