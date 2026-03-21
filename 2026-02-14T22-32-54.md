# Open-router Insight

A sleek macOS menu bar application for monitoring OpenRouter credits with richer usage insights.

![Open-router Insight](screenshots/1.png)
![Open-router Insight](screenshots/2.png)

## Features

- **Real-time Credit Monitoring**: Display your OpenRouter credit balance directly in the menu bar
- **Automatic Refresh**: Configurable refresh intervals (default: 5 minutes)
- **Manual Refresh Loading State**: "Loading..." is shown only on manual refresh, while interval refresh updates silently
- **Multi-Key Usage Views**: Switch API key usage between Slider, Table, and vertical List views
- **Slider Controls**: Arrow navigation, swipe gesture, indicator dots, and optional auto-slide every 5 seconds
- **Activity Analytics**: Embedded Spend / Requests / Tokens charts with filters by time (Today / 1 Week / 1 Month) and model
- **Chart Style Switcher**: Choose Bar chart or Line chart mode in activity analytics
- **Extended Time Ranges**: Additional 2 Weeks and 3 Weeks filters
- **Rankings Quick Access**: Top menu activity icon opens OpenRouter rankings page (`https://openrouter.ai/rankings`)
- **Top Model Usage Table**: In-menu ranking table computed from current activity filters
- **Provider + Model Breakdown**: Top Model Usage splits provider and model name into separate columns
- **Sortable Model Metrics**: Sort Top Model Usage by provider, total credit used, total requests, or total tokens (ascending/descending)
- **Selectable Ranking Size**: Choose Top 5 / 10 / 15 / 20 rows
- **Key Utilization Ranking**: Dedicated ranking table for keys by used/limit percentage with sortable columns
- **Model Concentration Insight**: Pie chart for Top 5 model spend share plus "Others" (rank 6+)
- **Key Anomaly Alerts**: Local macOS notification when daily key usage spikes above weekly rolling baseline
- **Activity Status Indicator**: Dedicated Activity section with live data indicator
- **Low Balance Warning**: Orange warning label appears in-menu when credit/limit nears threshold
- **Secure Configuration**: API key configuration with connection testing
- **Launch at Login**: Optional automatic startup when you log in
- **Settings Panel**: Easy-to-use configuration window
- **Alert Toggles in Settings**: Enable or disable key anomaly and low-credit alerts independently
- **Native Popover UX**: Popover closes when clicking outside

## Screenshots

### Menu Bar Display

The app shows your current available credit ($98.1809 in the example) directly in a dropdown menu.

### Settings Window

- Toggle credit monitoring on/off
- Set launch at login preferences
- Configure refresh intervals
- Securely enter and test your OpenRouter API key

## Requirements

- macOS 15.4 or later
- OpenRouter API account and API key
- Xcode 16.3 or later (for development)

## Installation

### From Release

1. Download the latest release from the [Releases](../../releases) page
2. Extract the .zip file
3. Move the application to your Applications folder
4. Launch the app and grant necessary permissions when prompted

### From Source

1. Clone this repository:

   ```bash
   git clone https://github.com/kittizz/OpenRouterCreditMenuBar.git
   ```

2. Open `OpenRouterCreditMenuBar.xcodeproj` in Xcode
3. Build and run the project (⌘+R)

## Setup & Configuration

1. **Get Your API Key**:
   - Visit [OpenRouter](https://openrouter.ai) and create an account
   - Navigate to your API keys section
   - Generate a new API key

2. **Configure the App**:
   - Launch Open-router Insight
   - Click the menu bar icon and select "Settings"
   - Enter your OpenRouter API key in the "API Configuration" section
   - Click "Test Connection" to verify your API key works
   - Adjust refresh interval as needed (default: 5 minutes)
   - Optionally enable "Open at Login" for automatic startup

3. **Start Monitoring**:
   - Enable "Credit Monitoring" in settings
   - Your credit balance will appear in the menu bar
   - Click "Refresh" anytime to update manually

## Usage

- **View Credits**: Click the menu bar icon to see available credit, enabled key count, and last-used key
- **Credit & Keys Quick Links**: Click the credit value to open OpenRouter credits settings and click enabled keys to open key settings
- **Refresh**: Use the "Refresh" button to manually update your balance with explicit loading state
- **Rankings Shortcut**: Use the chart icon in the top row to open `https://openrouter.ai/rankings`
- **API Key Usage Modes**: Switch between Slider / Table / List views in the key usage section
- **Slider Navigation**: Use arrows, swipe, or dots; toggle Auto to rotate cards every 5 seconds
- **Activity Charts**: Use the dedicated Activity section and filter by time window and model
- **Chart Mode**: Switch between Bar and Line views (line mode renders one line per model)
- **Top Model Usage**: Review aggregated per-model usage from the same filters as the chart
- **Sorting and Top-N**: Sort by Provider / Credit / Requests / Tokens and select Top 5 / 10 / 15 / 20
- **Key Utilization Ranking**: Identify which keys are consuming the largest share of their limits
- **Model Concentration Pie**: Track whether spend is concentrated in Top 5 models or spread into Others
- **Settings**: Access configuration options through the Settings button
- **Quit**: Close the application using the Quit button

The menu bar will display your credit balance and update automatically based on your configured refresh interval.

## Activity Data Notes

- Activity is loaded from `GET https://openrouter.ai/api/v1/activity`
- This endpoint generally requires a management/provisioning-capable key
- If activity appears empty, check runtime logs for HTTP status and payload diagnostics
- Credits and key usage data are loaded from:
  - `GET https://openrouter.ai/api/v1/credits`
  - `GET https://openrouter.ai/api/v1/key`
  - `GET https://openrouter.ai/api/v1/keys`
- Key anomaly detection uses `usage_daily` vs `(usage_weekly / 7)` baseline from key usage payloads
- Alerting is de-duplicated per key per day to avoid notification spam
- OpenRouter rankings are currently opened via webpage link; this app does not depend on an official public rankings API

### Runtime Log Location

- Primary/fallback runtime log file:
  - `~/Library/Application Support/OpenRouterCreditMenuBar/Logs/runtime.log`
- The app writes events such as `fetch_activity_http`, `fetch_activity_payload_sample`, and `fetch_activity_success`

## Development

### Building from Source

1. **Prerequisites**:
   - macOS 15.4+ (deployment target)
   - Xcode 16.3+
   - Swift 5.0+

2. **Clone and Build**:

   ```bash
   git clone <repository-url>
   cd OpenRouterCreditMenuBar
   ./scripts/build.sh
   ```

3. **Build and Install**:

   ```bash
   ./scripts/build.sh --install
   ```

   This builds the app and installs it to `/Applications/Open-router Insight.app`.

4. **Build Output**:
   - Built app: `./build/Build/Products/Release/Open-router Insight.app`
   - The app is signed for development but not for distribution.

### Build Script Options

- `./scripts/build.sh` — Build only (creates app in `./build/...`)
- `./scripts/build.sh --install` — Build and install to `/Applications`
- `./scripts/build.sh --help` — Show usage help

### Project Structure

- `OpenRouterCreditMenuBar/` — Main SwiftUI app source
- `scripts/build.sh` — Build and install automation
- `Taskfile.yml` — Extended build/release automation (optional)
- `README.md` — This file

### Release Automation (Optional)

If you have `gh` CLI installed and authenticated:

```bash
task release  # Full release pipeline (build + GitHub release)
```

## Security & Permissions

- **Network**: Required for OpenRouter API calls
- **Notifications**: Required for key anomaly and low-credit alerts
- **File System**: Logs are written to app bundle resources
- **No Keychain**: API key stored in UserDefaults (plain text)

## Activity Data Notes

- Credit and key usage data come from OpenRouter API endpoints (`/api/v1/credits`, `/api/v1/key`, `/api/v1/keys`).
- Activity data comes from `/api/v1/activity` and is cached locally to avoid excessive API calls.
- Activity entries are parsed with flexible date handling (ISO8601 and `yyyy-MM-dd HH:mm:ss`).
- Key anomaly detection uses a 7-day rolling average baseline and triggers a local macOS notification when daily usage exceeds `2.0x` the baseline with a minimum daily usage of `1.0`. Notifications are deduplicated per day to avoid spam.
- All alert settings are persisted in UserDefaults and can be toggled in the app settings.

## Privacy

- Your API key is stored locally and never transmitted except to OpenRouter's official API
- No usage data or personal information is collected

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License [LICENSE](LICENSE)

## Support

If you encounter any issues or have questions:

- [Open an issue](../../issues) on GitHub
- Check existing issues for common solutions

---

**Note**: This application is not officially affiliated with OpenRouter. It's a community-developed tool for monitoring API credits.
