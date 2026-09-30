.PHONY: build run release dist publish test check-accessibility smoke-test

build:
	bash scripts/build-app.sh

run: build
	open "Optimal Layout.app"

release:
	bash scripts/build-app.sh release

dist:
	bash scripts/release-macos.sh

publish:
	bash scripts/publish-release.sh

test:
	swift test

smoke-test:
	bash scripts/smoke-test.sh

check-accessibility:
	@mkdir -p .build
	@> .build/accessibility-check.log
	open -n -W "Optimal Layout.app" --stdout "$(CURDIR)/.build/accessibility-check.log" --args --check-accessibility
	@cat .build/accessibility-check.log
	@grep -qx 'Accessibility: allowed' .build/accessibility-check.log
