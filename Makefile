APP_NAME   = Aerie
BUILD_DIR  = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS   = $(APP_BUNDLE)/Contents
MACOS      = $(CONTENTS)/MacOS
RESOURCES  = $(CONTENTS)/Resources
CERT_NAME  = AerieDev
DIST_DIR   = dist
ARCH       = $(shell uname -m)
ZIP_NAME   = $(APP_NAME)-macOS-$(ARCH).zip
ICON_SRC   = Sources/Aerie/Resources/Assets.xcassets/AppIcon.appiconset
ICNS_OUT   = Resources/AppIcon.icns

.PHONY: build app run clean icon install test

build:
	swift build -c release

icon:
	@bash scripts/build-icns.sh "$(ICON_SRC)" "$(ICNS_OUT)"

app: build icon
	rm -rf $(APP_BUNDLE)
	mkdir -p $(MACOS) $(RESOURCES)
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS)/$(APP_NAME)
	@# SwiftPM emits each target's resources as a sibling .bundle dir
	@# (Bundle.module finds them via Bundle.main.resourceURL). Ship them
	@# under Contents/Resources/. Bundles without an Info.plist (e.g.
	@# our own Aerie_Aerie.bundle, which only contains the noise asset)
	@# get a minimal one synthesised so codesign accepts them.
	@for b in $(BUILD_DIR)/*.bundle; do \
		[ -e "$$b" ] || continue; \
		base=$$(basename "$$b"); \
		dest="$(RESOURCES)/$$base"; \
		cp -R "$$b" "$$dest"; \
		if [ ! -f "$$dest/Info.plist" ]; then \
			id="dev.echoulen.$$(echo $$base | sed 's/\.bundle$$//')"; \
			/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $$id" "$$dest/Info.plist" >/dev/null; \
			/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$$dest/Info.plist" >/dev/null; \
			/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string BNDL" "$$dest/Info.plist" >/dev/null; \
			echo "Synthesised Info.plist for $$base"; \
		fi; \
	done
	cp Sources/Aerie/Resources/Info.plist $(CONTENTS)/Info.plist
	cp $(ICNS_OUT) $(RESOURCES)/AppIcon.icns
	@HASH=$$(git rev-parse --short=7 HEAD 2>/dev/null); \
	if [ -n "$$HASH" ]; then \
		/usr/libexec/PlistBuddy -c "Delete :GitCommitSHA" $(CONTENTS)/Info.plist >/dev/null 2>&1 || true; \
		/usr/libexec/PlistBuddy -c "Add :GitCommitSHA string $$HASH" $(CONTENTS)/Info.plist; \
		echo "Injected GitCommitSHA=$$HASH"; \
	fi; \
	DATE=$$(git log -1 --format=%cd --date=format:'%Y%m%d' 2>/dev/null); \
	if [ -n "$$DATE" ]; then \
		/usr/libexec/PlistBuddy -c "Delete :GitCommitDate" $(CONTENTS)/Info.plist >/dev/null 2>&1 || true; \
		/usr/libexec/PlistBuddy -c "Add :GitCommitDate string $$DATE" $(CONTENTS)/Info.plist; \
		echo "Injected GitCommitDate=$$DATE"; \
	fi; \
	COUNT=$$(git rev-list --count HEAD 2>/dev/null); \
	if [ -n "$$COUNT" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$COUNT" $(CONTENTS)/Info.plist; \
		echo "Injected CFBundleVersion=$$COUNT"; \
	fi
	@bash scripts/ensure_signing_cert.sh "$(CERT_NAME)" || true
	@if security find-certificate -c "$(CERT_NAME)" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then \
		codesign --force --deep --sign "$(CERT_NAME)" $(APP_BUNDLE); \
	else \
		echo "⚠ Using ad-hoc signing (TCC permissions may not persist after rebuilds)"; \
		codesign --force --deep --sign - $(APP_BUNDLE); \
	fi

run: app
	open $(APP_BUNDLE)

install: app
	@# Stop any running instance (installed app or dev build with the same
	@# process name) before we swap the bundle. Steps:
	@#   1. Apple Events Quit  — lets AppKit save state cleanly.
	@#   2. 5 s grace          — polled, not a fixed sleep.
	@#   3. SIGKILL            — required because AerieAppDelegate's
	@#                           applicationShouldTerminate can swallow
	@#                           SIGTERM, leaving a "ghost" process that
	@#                           still maps the old binary in memory.
	@#   4. Wait for reaping   — without this, `cp -R` races the dying
	@#                           process and `open` later just activates
	@#                           the ghost instead of launching the fresh
	@#                           bundle.
	@echo "Stopping any running $(APP_NAME)…"
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5; do \
		pgrep -x $(APP_NAME) >/dev/null 2>&1 || break; \
		sleep 1; \
	done
	@pkill -9 -x $(APP_NAME) 2>/dev/null || true
	@while pgrep -x $(APP_NAME) >/dev/null 2>&1; do sleep 0.2; done
	rm -rf /Applications/$(APP_BUNDLE)
	cp -R $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(ZIP_NAME)
	@echo "Created $(DIST_DIR)/$(ZIP_NAME)"
	rm -rf $(APP_BUNDLE)
	open /Applications/$(APP_BUNDLE)

clean:
	rm -rf .build $(APP_BUNDLE) $(DIST_DIR) $(ICNS_OUT)

test:
	swift test
