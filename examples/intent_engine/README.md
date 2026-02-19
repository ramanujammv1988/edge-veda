# Intent Engine

On-device smart home control with LLM function calling -- speak naturally and watch your home respond.

> Built with [Edge Veda SDK](../../flutter) -- on-device LLM inference for Flutter

<!-- Screenshot placeholder -->
<!-- ![Intent Engine screenshot](screenshot.png) -->

## SDK Features Demonstrated

- **ChatSession.sendWithTools** -- multi-round LLM tool calling for natural language intent parsing
- **ToolDefinition** + **ToolRegistry** -- structured tool schemas with parameter validation
- **ChatTemplateFormat.qwen3** -- Hermes-style tool call template for Qwen3 models
- **ModelManager** -- automatic model download with progress tracking
- **EdgeVeda** -- on-device inference with Qwen3-0.6B (no cloud, no pre-programmed phrases)

## Features

- Natural language intent parsing via on-device LLM (Qwen3-0.6B)
- 5 device types: lights (brightness + color temp), thermostat, locks, TV, fan
- 3 rooms with 10 virtual devices
- Real-time animated device state dashboard
- Transparent action log showing LLM tool call decisions with timestamps and arguments
- Conversational context across turns
- Pluggable Home Assistant REST API connector
- 100% offline after model download

## Prerequisites

- iOS device (iPhone 12 or later recommended)
- Xcode 26+ with iOS 18+ SDK
- Flutter 3.16+
- ~397 MB free storage for Qwen3-0.6B model download

## Quick Start

1. Clone the repo and navigate to the example:
   ```bash
   git clone https://github.com/anthropics/edge-veda.git
   cd edge-veda/examples/intent_engine
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Build the XCFramework (see [main SDK README](../../flutter/README.md) for details):
   ```bash
   cd ../../ios && ./build_xcframework.sh && cd -
   ```

4. Run the app:
   ```bash
   flutter run
   ```
   Or open `ios/Runner.xcworkspace` in Xcode and run from there.

5. First run downloads Qwen3-0.6B (~397 MB) with a progress bar. Subsequent launches are instant.

## How It Works

```
User Input ("I'm heading to bed")
        |
        v
ChatSession.sendWithTools()
        |
        v
Qwen3-0.6B (on-device LLM)
        |
        v
ToolCall objects (set_light, set_lock, set_tv, ...)
        |
        v
HomeState.applyAction() per tool call
        |
        v
Animated UI updates
```

The LLM receives a system prompt that includes every device ID and its current state. When the user speaks naturally, the model decides which tools to call and with what arguments. The app executes each tool call against `HomeState`, which notifies the UI to animate the changes.

After each intent, the `ChatSession` is recreated with a fresh system prompt reflecting the updated home status. This ensures the model always reasons about the current state.

### Tool Definitions

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `set_light` | Turn lights on/off, adjust brightness and color temperature | `device_id`, `is_on`, `brightness` (0-100), `color_temp` (2700-6500K) |
| `set_thermostat` | Set temperature and operating mode | `device_id`, `target_temp` (60-85F), `mode` (heat/cool/auto/off) |
| `set_lock` | Lock or unlock doors | `device_id`, `is_locked` |
| `set_tv` | Control TV power, input source, and volume | `device_id`, `is_on`, `input` (hdmi1/hdmi2/streaming), `volume` (0-100) |
| `set_fan` | Set fan speed | `device_id`, `speed` (0=off, 1=low, 2=medium, 3=high) |
| `get_home_status` | Query current state of all devices | (none) |

### System Prompt Strategy

The system prompt explicitly lists all 10 device IDs and their current states. This is essential for small models (0.6B parameters) that cannot infer device IDs from context. After each intent is processed, the session is recreated with updated state so the next command reflects reality.

## Home Assistant Integration

The `HomeAssistantConnector` implements the `ActionRouter` interface and maps each tool call to the corresponding Home Assistant REST API endpoint. Currently it logs curl commands without making HTTP calls -- ready to wire to a real instance.

### Setup

1. **Get a Long-Lived Access Token:**
   - Open your Home Assistant UI
   - Go to Profile > Security > Long-Lived Access Tokens
   - Click "Create Token" and copy it

2. **Find your entity IDs:**
   - Go to Developer Tools > States in your HA UI
   - Entity IDs look like: `light.living_room`, `climate.thermostat`, etc.

3. **Configure the connector:**
   ```dart
   final ha = HomeAssistantConnector(
     baseUrl: 'http://homeassistant.local:8123',
     bearerToken: 'your-long-lived-access-token',
   );
   ```

4. **Replace the print() calls** in `HomeAssistantConnector.executeAction()` with actual `http.post()` calls using the endpoint, headers, and body from `HomeAssistantAction`.

### REST API Mapping

| Tool | HA Endpoint |
|------|-------------|
| `set_light` (on) | `POST /api/services/light/turn_on` |
| `set_light` (off) | `POST /api/services/light/turn_off` |
| `set_thermostat` | `POST /api/services/climate/set_temperature` |
| `set_lock` (lock) | `POST /api/services/lock/lock` |
| `set_lock` (unlock) | `POST /api/services/lock/unlock` |
| `set_tv` (on) | `POST /api/services/media_player/turn_on` |
| `set_tv` (off) | `POST /api/services/media_player/turn_off` |
| `set_fan` (on) | `POST /api/services/fan/set_percentage` |
| `set_fan` (off) | `POST /api/services/fan/turn_off` |

## Example Commands

| Command | What happens |
|---------|-------------|
| "I'm heading to bed" | Dims/turns off lights, locks doors, turns off TV |
| "Movie time" | Dims living room lights, turns on TV to streaming |
| "I'm leaving" | All lights off, locks engaged, thermostat to eco |
| "It's too bright in here" | Reduces brightness of currently on lights |
| "Make it cozy" | Warm color temp, lower brightness, fan off |

These are not pre-programmed -- the LLM interprets the intent and decides which devices to change.

## Architecture

The app never imports `edge_veda` directly in UI code. All SDK interaction is wrapped behind `IntentService`:

| File | Wraps | Purpose |
|------|-------|---------|
| `lib/services/intent_service.dart` | `EdgeVeda`, `ChatSession`, `ModelManager`, `ToolRegistry` | Downloads Qwen3-0.6B, creates ChatSession with 6 tool definitions, processes natural language intents via `sendWithTools` |
| `lib/services/home_assistant.dart` | -- | Maps tool calls to Home Assistant REST API endpoints with curl generation |
| `lib/models/device_state.dart` | -- | 5 immutable device state types with `copyWith` and `toStatusString` |
| `lib/models/home_state.dart` | -- | Reactive state model: 3 rooms, 10 devices, action log, `ActionRouter` interface |
| `lib/widgets/device_card.dart` | -- | Animated device cards for all 5 device types |
| `lib/widgets/action_log_panel.dart` | -- | Scrollable action log with timestamps, tool names, and JSON arguments |
| `lib/main.dart` | -- | App shell: setup screen, home dashboard, chat input, suggestion chips |

## Adapting for Your App

1. Replace the path dependency in `pubspec.yaml` with a pub.dev dependency:
   ```yaml
   edge_veda: ^1.0.0
   ```

2. Copy `lib/services/intent_service.dart` as a starting point for your own tool-calling service.

3. Define your own `ToolDefinition` objects for your domain (not limited to smart home).

4. The `ActionRouter` interface makes it easy to swap between local simulation and real device backends.
