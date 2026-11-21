VERSION ?= 1.0.0
BUILD ?= 1
GITHUB_REPO ?= kobenguyent/Velora
XCODE_DEV_DIR := $(shell [ -d /Applications/Xcode.app/Contents/Developer ] && echo /Applications/Xcode.app/Contents/Developer)

.PHONY: test run build app install install-user dmg clean

test:
	$(if $(XCODE_DEV_DIR),DEVELOPER_DIR=$(XCODE_DEV_DIR)) swift test

run:
	swift run Velora

build:
	swift build -c release

app:
	./scripts/build-app.sh --arch native --version $(VERSION) --build $(BUILD) --github-repo $(GITHUB_REPO)

install:
	./scripts/install-local.sh --version $(VERSION) --build $(BUILD) --github-repo $(GITHUB_REPO)

install-user:
	./scripts/install-local.sh --user --version $(VERSION) --build $(BUILD) --github-repo $(GITHUB_REPO)

dmg:
	./scripts/package-release.sh --arch universal --version $(VERSION) --build $(BUILD) --github-repo $(GITHUB_REPO)

clean:
	rm -rf .build dist
