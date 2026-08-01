# Maspice — thin task runner over scripts/. Run `make` (or `make help`) for the list.
# Sets DEVELOPER_DIR so you never have to remember the prefix. The scripts in
# scripts/ stay the source of truth.

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
APP_NAME := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)

.DEFAULT_GOAL := help

.PHONY: help doctor build run test test-session all icon debug release check-version clean distclean

help: ## Show this help
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

doctor: ## Check Xcode, Swift, SDK, and the SwiftSpice release
	@./scripts/doctor.sh

build: ## Build and assemble build/Maspice.app
	@./scripts/build-app.sh

run: ## Open build/Maspice.app
	@open "build/$(APP_NAME).app"

test: ## Run VV parsing, session logic, and SwiftSpice integration tests
	@( cd Packages/VVConfig && swift run --disable-sandbox vvcheck )
	@swift test --disable-sandbox --package-path Packages/SpiceSessionLogic
	@swift test --disable-sandbox

test-session: ## Run focused session cleanup and command-state tests
	@swift test --disable-sandbox --package-path Packages/SpiceSessionLogic

all: ## Verify the environment, test, and assemble the app
	@$(MAKE) doctor
	@$(MAKE) test
	@$(MAKE) build

icon: ## Validate Resources/AppIcon.icon and refresh the README preview
	@./scripts/make-icon.sh

debug: ## Launch a direct SPICE connection from the terminal: make debug VV=conn.vv
	@./scripts/debug-run.sh $(VV)

release: ## Cut a release (prompts before publishing):  make release VERSION=0.2.1
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=X.Y.Z"; exit 1; }
	@./scripts/release.sh $(VERSION)

check-version: ## Assert Info.plist / CHANGELOG / tag versions agree
	@./scripts/check-version.sh

clean: ## Remove build output (build/)
	@rm -rf build/ && echo "removed build/"

distclean: clean ## Also remove generated SwiftPM state
	@rm -rf .build/ .swiftpm/ Packages/VVConfig/.build/ Packages/VVConfig/.swiftpm/ Packages/SpiceSessionLogic/.build/ Packages/SpiceSessionLogic/.swiftpm/
	@echo "removed generated SwiftPM state"
