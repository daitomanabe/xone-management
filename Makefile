SWIFTC ?= swiftc
APP_NAME := Xone K2 OSC LED Bridge
APP_DIR := apps/$(APP_NAME).app

.PHONY: build-native build-bridge build-m4l-generator bundle-bridge-app build-m4l start list test all-off clean

build-native: build-bridge build-m4l-generator bundle-bridge-app

build-bridge:
	$(SWIFTC) -O native/osc-led-bridge/main.swift -o scripts/osc-led-bridge

build-m4l-generator:
	$(SWIFTC) -O native/build-m4l/main.swift -o scripts/build-m4l

bundle-bridge-app: build-bridge
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	$(SWIFTC) -O native/osc-led-bridge-app/main.swift -o "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp native/osc-led-bridge-app/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp scripts/osc-led-bridge "$(APP_DIR)/Contents/Resources/osc-led-bridge"

build-m4l:
	scripts/build-m4l

start:
	scripts/osc-led-bridge start

list:
	scripts/osc-led-bridge list

test:
	scripts/osc-led-bridge test

all-off:
	scripts/osc-led-bridge all-off

clean:
	rm -rf "$(APP_DIR)"
