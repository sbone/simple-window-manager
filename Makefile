.PHONY: build run release test

build:
	bash scripts/build-app.sh

run: build
	open "Optimal Layout.app"

release:
	bash scripts/build-app.sh release

test:
	swift test
