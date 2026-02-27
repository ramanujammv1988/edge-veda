# Changelog

## [0.2.0] - 2026-02-27

### Fixed
- **P0**: Podfile linkage mode — use `use_modular_headers!` instead of `use_frameworks!`
- **P0**: Podfile existence handling — patch AFTER `flutter pub get`, not before
- **P0**: Class name collision — `QuickstartScreen` avoids duplicate `ChatScreen`
- **P0**: download_model path — saves to `project_path/models/`, not `/tmp/`
- **P1**: add_capability wires imports and navigation into `main.dart`
- **P1**: add_capability runs `flutter pub get` after adding dependencies
- **P1**: create_project uses `model_id` parameter instead of hardcoded model
- **P2**: Idempotent directory creation (no crash on re-run)
- **P2**: check_environment runs checks in parallel (`Promise.all`)
- Correct Dart model constants (verified against SDK source)
- Eliminate curl command injection via shell argument escaping
- Robust Podfile patch with 3-way detection (replace/insert/report)
- iOS deployment target aligned with SDK podspec (13.0)
- Real dependency version constraints (image_picker, record, file_picker)

### Added
- 8 smoke tests covering all tool validation paths
- Documentation alignment between tool output and actual behavior

## [0.1.0] - 2026-02-26

### Added
- Initial MCP server with 6 tools: `check_environment`, `list_models`, `create_project`, `add_capability`, `download_model`, `run`
- npx-based zero-install usage
- TypeScript + Zod schema validation
