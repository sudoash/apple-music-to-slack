# Apple Music to Slack

Update your Slack status with the current song playing via the Music.app. Now available as a convenient menu bar application!

## Setup

1. Setup the slack app:

   1. Create a new app https://api.slack.com/apps?new_app=1 providing a name and
       selecting the desired Slack Workspace that you’re going to run Apple Music to Slack on;

   2. Under “Add features and functionality” select the “Permissions” section;

   3. Scroll down to "User Token Scopes" and add `users.profile:write`;

   4. Scroll up to the top of the page and click “Install App to Workspace”;

   5. Copy the `OAuth Access Token`; you’ll need it to configure `apple-music-to-slack`;

2. Clone the repo & compile with `swift build -c release`;

3. Configure `apple-music-to-slack`:

   ```sh
   readonly CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/apple-music-to-slack"
   install -d "$CONF_DIR"
   echo 'slack_token = "xoxp-11111-11111-11111-111111111111"' >"$CONF_DIR/settings.toml"
   ```

4. Run the menu bar application:

   ```sh
   ./.build/release/apple-music-to-slack
   ```

   The app will appear in your menu bar with a ♪ icon. Click on it to:
   - Start/Stop monitoring
   - View current status 
   - Access preferences
   - Quit the application

   Alternatively, you can set the Slack token via environment variable:
   ```sh
   export AMTS_SLACK_TOKEN=xoxp-11111-11111-11111-111111111111
   ./.build/release/apple-music-to-slack
   ```

5.  Success! 🎶

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
