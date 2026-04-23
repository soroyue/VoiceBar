.PHONY: all build run install clean generate

BUNDLE_ID = com.voicebar.app
APP_NAME = VoiceBar
BUILD_DIR = build
APP_PATH = $(BUILD_DIR)/$(APP_NAME).app
SPM_DIR = VoiceBar.xcodeproj

all: generate build

generate:
	xcodegen generate --spec project.yml --project .

build: generate
	mkdir -p $(BUILD_DIR)
	xcodebuild -project $(SPM_DIR) \
		-configuration Debug \
		-buildSettings PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		-build

run: build
	open $(APP_PATH)

install: build
	cp -R $(APP_PATH) /Applications/

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(SPM_DIR)
	rm -rf VoiceBar.xcodeproj

distclean: clean
	rm -rf $(BUILD_DIR)
