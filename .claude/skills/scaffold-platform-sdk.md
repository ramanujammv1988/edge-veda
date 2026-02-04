---
name: scaffold-platform-sdk
description: Generate boilerplate SDK structure for a new platform
allowed-tools: Write, Bash, Read
---

# Scaffold Platform SDK

Generate a complete SDK scaffold for the specified platform.

## Usage
```
/scaffold-platform-sdk <platform>
```

Where `<platform>` is one of: `swift`, `kotlin`, `react-native`, `web`

## What Gets Created

### For Swift:
```
swift/
├── Package.swift
├── Sources/EdgeVeda/
│   ├── EdgeVeda.swift
│   ├── Config.swift
│   └── Types.swift
├── Tests/EdgeVedaTests/
└── README.md
```

### For Kotlin:
```
kotlin/
├── build.gradle.kts
├── src/main/kotlin/com/edgeveda/
│   ├── EdgeVeda.kt
│   ├── Config.kt
│   └── Types.kt
├── src/test/kotlin/
└── README.md
```

### For React Native:
```
react-native/
├── package.json
├── src/
│   ├── index.tsx
│   ├── NativeEdgeVeda.ts
│   └── types.ts
├── ios/
├── android/
└── README.md
```

### For Web:
```
web/
├── package.json
├── src/
│   ├── index.ts
│   ├── worker.ts
│   └── types.ts
├── rollup.config.js
└── README.md
```

Follow Edge Veda naming conventions and API patterns established in the core.
