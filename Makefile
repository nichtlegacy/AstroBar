.PHONY: build app run cli dump test icon install dmg site serve clean

# Build and install into /Applications, then launch.
install: app
	@pkill -f "AstroBar.app/Contents/MacOS/AstroBar" 2>/dev/null || true
	@sleep 1
	rm -rf /Applications/AstroBar.app
	cp -R AstroBar.app /Applications/AstroBar.app
	@xattr -dr com.apple.quarantine /Applications/AstroBar.app 2>/dev/null || true
	open /Applications/AstroBar.app
	@echo "✓ Installed to /Applications/AstroBar.app"

# Build a distributable disk image.
dmg: app
	rm -f AstroBar.dmg
	hdiutil create -volname AstroBar -srcfolder AstroBar.app -ov -format UDZO AstroBar.dmg
	@echo "✓ Created AstroBar.dmg"

# Build the landing page into _site/.
site:
	./scripts/build_site.sh

# Build the landing page and serve it on 0.0.0.0:8000.
serve:
	./scripts/build_site.sh --serve

# Regenerate the app icon (.icns).
icon:
	./scripts/build_icon.sh

# Debug build of every product.
build:
	swift build

# Assemble a release .app bundle.
app:
	./scripts/package_app.sh release

# Build + launch the app.
run: app
	open AstroBar.app

# Build the diagnostic CLI.
cli:
	swift build --product astrobar-cli

# Dump every value the connected base station exposes.
dump:
	swift run astrobar-cli dump

test:
	swift test

clean:
	rm -rf .build AstroBar.app
