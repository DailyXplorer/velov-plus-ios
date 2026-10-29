SHELL := /bin/zsh
export PATH := /opt/homebrew/bin:$(PATH)

PROJECT := VelovCompagnon.xcodeproj
SCHEME := VelovCompagnon
DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData/VelovCompagnon-make
DEVICE := $(DEVICE)
SIM_NAME := Velov iPhone 17 Pro
SIM_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
APP_DEVICE := $(DERIVED)/Build/Products/Debug-iphoneos/VelovCompagnon.app
LOG := $(DERIVED)/logs

.PHONY: project assets build build-unsigned build-sim test smoke install snapshots clean

assets:
	python3 scripts/fetch-assets.py
	test -f App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png || swift scripts/make-icon.swift

project: assets
	/opt/homebrew/bin/xcodegen generate --quiet

## Device build, signed with the personal team (needs the login keychain unlocked: run it from the GUI session).
build: project
	mkdir -p $(LOG)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'generic/platform=iOS' \
	  -derivedDataPath $(DERIVED) -allowProvisioningUpdates build 2>&1 | tee $(LOG)/build.log | grep -E "error:|warning:|BUILD" ; \
	  exit $${pipestatus[1]}

## Device build without signing: proves the app compiles for iphoneos.
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

## Core logic on the macOS host: models, normalisation, dates, bike score, error maps, networking and auth against mocked URLProtocol.
test:
	cd Packages/VelovCore && swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -5 ; exit $${pipestatus[1]}

## Public GETs only (GBFS stations, bikes of station 2002 with the anonymous app token).
smoke:
	cd Packages/VelovCore && VELOV_LIVE=1 swift test --filter LiveSmokeTests 2>&1 | grep -E "LIVE|error|Executed" ; exit $${pipestatus[1]}

install:
	xcrun devicectl device install app --device $(DEVICE) $(APP_DEVICE)

## PNG renders of the key screens with sample data, in the simulator.
snapshots: build-sim
	SIM_NAME="$(SIM_NAME)" SIM_TYPE="$(SIM_TYPE)" DERIVED="$(DERIVED)" zsh scripts/snapshots.sh

clean:
	rm -rf $(DERIVED) $(PROJECT)
