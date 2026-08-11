# Medical Extract

On-device medical document extraction powered by MedGemma. Extract structured data from prescriptions and lab reports — 100% offline, HIPAA-friendly by design.

## Features

- **Prescription Extraction**: Drug name, dosage, frequency, prescriber, date
- **Lab Report Extraction**: Test name, value, unit, reference range, flag
- **Follow-up Q&A**: RAG-powered questions about your extracted documents
- **100% On-Device**: Your medical data never leaves your device
- **Structured Output**: JSON schema validation via `sendStructured()`

## Setup

```bash
cd examples/medical_extract
flutter pub get
flutter run
```

First run downloads ~1.7 GB of models (MedGemma 2B + embedding model).

## Usage

1. Select mode: **Prescriptions** or **Lab Reports**
2. Paste document text into the input area
3. Tap **Extract** to run structured extraction
4. View results in formatted cards
5. Ask follow-up questions in the chat interface

## Models Used

- **MedGemma 2B** (Q4_K_M, ~1.6 GB) — Medical-specialized LLM
- **All MiniLM L6 v2** (F16, ~46 MB) — Embeddings for RAG

## Disclaimer

This app is for educational and informational purposes only. It is NOT medical advice. Always consult a qualified healthcare provider.
