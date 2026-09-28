.PHONY: build run release

build:
	bash scripts/build-app.sh

run: build
	open "Optimal Layout.app"

release:
	bash scripts/build-app.sh release
