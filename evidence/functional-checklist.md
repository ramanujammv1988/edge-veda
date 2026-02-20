# Functional Checklist — Android Vulkan + iOS Memory Pressure Parity

Tested by: [PENDING — requires human]
Device: [PENDING — requires physical Android + iOS devices]
Date: [PENDING]
Build: release

## Core (always check)
- [ ] App launches without crash
- [ ] Model loads successfully
- [ ] `generateStream()` -> tokens arrive, stream terminates

## Vulkan Backend (if MR touches inference path)
- [ ] On Android: Settings screen shows "Vulkan GPU" (not "CPU")
- [ ] On Android: `logcat` shows `ggml_vulkan_init` during model load
- [ ] On Android: Inference produces correct output (same as CPU)
- [ ] On low-end Android (no Vulkan): graceful fallback to CPU

## iOS Memory Pressure (if MR touches EventChannels)
- [ ] On iOS: Debug > Simulate Memory Warning -> event received in Flutter
- [ ] On iOS: Memory pressure level shows in UI ("critical")
- [ ] On iOS: No crash from memory pressure events

## Lifecycle
- [ ] Background -> foreground -> app recovers
- [ ] No crash over 10-minute session (Android)
- [ ] No crash over 10-minute session (iOS)

## Observations
Thermal at start: [X]
Thermal at end: [X]
RSS after model load: [X] MB
RSS at end: [X] MB
Android backend reported: [Vulkan / CPU]
