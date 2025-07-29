.PHONY: app install clean help icon

help:
	@echo "Apple Music to Slack - Build Targets:"
	@echo ""
	@echo "  app     - Build the .app bundle"
	@echo "  install - Build and install to /Applications"
	@echo "  clean   - Clean build artifacts"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Quick start:"
	@echo "  make app && ./install.sh"
	@echo ""
	@echo "Custom icon:"
	@echo "  ./create_icon.sh your_icon.png && make app"

app:
	@echo "Building Apple Music to Slack.app..."
	@./build_app.sh

install: app
	@echo "Installing Apple Music to Slack.app to /Applications..."
	@cp -r "build/Apple Music to Slack.app" /Applications/
	@echo "✅ Successfully installed to /Applications/"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build
	@rm -rf .build
	@echo "✅ Clean complete"
