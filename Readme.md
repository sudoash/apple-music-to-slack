# Apple Music to Slack

Update your Slack status with the current song playing via the Music.app.

## Setup

1. Setup the slack app:

   1. Create a new app https://api.slack.com/apps?new_app=1 providing a name and
       selecting the desired Slack Workspace that you’re going to run Apple Music to Slack on;

   2. Under “Add features and functionality” select the “Permissions” section;

   3. Scroll down to "User Token Scopes" and add `users.profile:write`;

   4. Scroll up to the top of the page and click “Install App to Workspace”;

   5. Copy the `OAuth Access Token`; you’ll need it to configure `apple-music-to-slack`;

2. Clone the repo & build the application:

   ```sh
   # Build the .app bundle
   make app
   
   # Or build and install directly to Applications
   make install
   ```

   Alternatively, you can build manually:
   ```sh
   ./build_app.sh
   ```

3. Install the application:

   ```sh
   # Copy the app to Applications folder
   cp -r "build/Apple Music to Slack.app" /Applications/
   ```

4. Configure `apple-music-to-slack`:

   ```sh
   readonly CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/apple-music-to-slack"
   install -d "$CONF_DIR"
   echo 'slack_token = "xoxp-11111-11111-11111-111111111111"' >"$CONF_DIR/settings.toml"
   ```

5. Launch the application:

   You can now launch "Apple Music to Slack" from:
   - Applications folder in Finder
   - Spotlight search (⌘+Space)
   - Or run directly: `open "/Applications/Apple Music to Slack.app"`

   The app will appear in your menu bar with a ♪ icon. Click on it to:
   - Start/Stop monitoring
   - View current status 
   - Access preferences
   - Quit the application

   Alternatively, you can set the Slack token via environment variable:
   ```sh
   export AMTS_SLACK_TOKEN=xoxp-11111-11111-11111-111111111111
   open "/Applications/Apple Music to Slack.app"
   ```

6.  Success! 🎶

## Building from Source

If you prefer to build manually:

```sh
# Clone the repository
git clone <repository-url>
cd apple-music-to-slack

# Build the app bundle
make app

# Install to Applications (optional)
make install

# Clean build artifacts
make clean
```

## Customizing the App Icon

The app includes a default green music note icon. To use your own icon:

1. Create a 1024x1024 PNG image
2. Run: `./create_icon.sh your_icon.png`
3. Move the generated `AppIcon.icns` to `Resources/`
4. Rebuild: `make clean && make app`

See [ICON.md](ICON.md) for detailed icon creation instructions.

## Features

- **Menu Bar Interface**: Easy-to-use menu bar application that runs in the background
- **Start/Stop Control**: Toggle monitoring on and off from the menu
- **Real-time Status**: View current song information and monitoring status
- **Configuration**: Supports both config file and environment variable setup
- **Smart Updates**: Only updates Slack when the song changes to avoid rate limiting
- **Status Restoration**: Optionally restores your original Slack status when music stops

## Configuration Options

You can configure the following options in your `settings.toml` file:

```toml
slack_token = "xoxp-your-token-here"
include_album_name = true  # Include album name in status (default: true)
```

The app also supports these behaviors:
- **Random Emoji**: Currently uses music note emoji (♪)
- **Clear When Not Playing**: Restores original status when music stops (enabled by default)

> [!NOTE]  
> The app primarily gets the Slack token from the `AMTS_SLACK_TOKEN` environment variable or from the `settings.toml` config file. The environment variable takes precedence.

## Prior Art

- <https://github.com/sbdchd/apple-music-to-slack>
- <https://github.com/ocxo/slacktunes>
- <https://github.com/josegonzalez/python-slack-tunes>
