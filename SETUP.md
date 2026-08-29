#### ReceiptAI Finance Assistant - Setup Guide

## Prerequisites

- Flutter SDK >= 3.3.0
- Dart SDK >= 3.3.0
- Firebase CLI
- FlutterFire CLI
- Ollama (for local AI)
- Android Studio / Xcode

---

## 1. Firebase Setup

### Create Firebase Project

```bash
# Install Firebase CLI
npm install -g firebase-tools
firebase login

# Create project at console.firebase.google.com
# Enable: Authentication, Firestore, Storage
```

### Enable Auth Providers

In Firebase Console > Authentication > Sign-in method:

- Enable **Email/Password**
- Enable **Google**

### Configure FlutterFire

```bash
dart pub global activate flutterfire_cli

# If flutterfire is in your PATH:
flutterfire configure --project=YOUR_PROJECT_ID

# Fallback (if you get "command not found: flutterfire"):
dart pub global run flutterfire_cli:flutterfire configure --project=YOUR_PROJECT_ID
```

This generates `lib/firebase_options.dart` with real keys.

### Deploy Firestore Rules

```bash
firebase deploy --only firestore:rules
firebase deploy --only storage
```

### Firestore Indexes

Create composite index in Firebase Console (or via `firestore.indexes.json`):

Collection: `receipts`

- Field: `userId` ASC
- Field: `createdAt` DESC

Collection: `expenses`

- Field: `userId` ASC
- Field: `date` DESC

---

## 2. Ollama Setup (Local AI)

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull the model (llama3.2 is fast and capable)
ollama pull llama3.2

# Start the server (runs on http://localhost:11434)
ollama serve

# Verify
curl http://localhost:11434/api/tags
```

The app reads `OLLAMA_BASE_URL` and `OLLAMA_MODEL` from `.env`.

### Switching AI Providers

To use a different provider, implement the `AIProvider` interface:

```dart
class OpenAIProvider implements AIProvider {
  @override
  String get name => 'openai:gpt-4o-mini';

  @override
  Future<String> complete({...}) async { ... }
  // etc.
}
```

Then swap the provider in `ai_service.dart`:

```dart
@riverpod
AIProvider aiProvider(Ref ref) {
  return OpenAIProvider(apiKey: Environment.openAiKey);
}
```

---

## 3. Flutter Setup

```bash
# Install dependencies
flutter pub get

# Run code generation (generates .g.dart files)
dart run build_runner build --delete-conflicting-outputs

# Run on device
flutter run
```

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

Add `google-services.json` from Firebase Console to `android/app/`.

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to scan receipts</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to select receipt images</string>
```

Add `GoogleService-Info.plist` from Firebase Console to `ios/Runner/`.

---

## 4. Fonts

Download Inter font family from https://fonts.google.com/specimen/Inter and place in `assets/fonts/`:

- `Inter-Regular.ttf`
- `Inter-Medium.ttf`
- `Inter-SemiBold.ttf`
- `Inter-Bold.ttf`

---

## Firestore Schema

### `receipts/{receiptId}`

```json
{
  "userId": "string",
  "imageUrl": "string (Firebase Storage URL)",
  "rawOcrText": "string | null",
  "storeName": "string | null",
  "receiptDate": "timestamp | null",
  "items": [
    {
      "id": "string",
      "name": "string",
      "quantity": "number",
      "unitPrice": "number",
      "totalPrice": "number"
    }
  ],
  "totalAmount": "number",
  "category": "string (enum: groceries|delivery|restaurants|...)",
  "status": "string (enum: pending|processing|completed|failed)",
  "createdAt": "timestamp",
  "ocrConfidence": "number (0.0-1.0)"
}
```

### `expenses/{expenseId}`

```json
{
  "userId": "string",
  "receiptId": "string",
  "category": "string",
  "amount": "number",
  "storeName": "string | null",
  "date": "timestamp",
  "createdAt": "timestamp"
}
```

---

## Architecture Overview

```
lib/
├── core/              # Router, config, errors
├── features/
│   ├── auth/          # Login, register, session
│   ├── receipts/      # Upload, OCR, scan flow
│   ├── expenses/      # Categorized spending data
│   ├── insights/      # AI-generated financial insights
│   └── dashboard/     # Home screen, charts
├── services/
│   ├── ai/            # AIProvider interface + OllamaProvider
│   ├── ocr/           # OcrService interface + MlKitOcrService
│   ├── storage/       # Firebase Storage wrapper
│   └── image/         # Compression
└── shared/            # Theme, reusable widgets
```

Each feature follows:

- `domain/` - entities, repository interfaces, use cases
- `data/` - models (Firestore serialization), repository implementations
- `presentation/` - Riverpod providers, screens, widgets

### Key Architectural Decisions

**AIProvider abstraction**: The `AIProvider` interface decouples all AI logic from Ollama specifics. Switching to Claude, OpenAI, or Ollama Cloud requires implementing one interface and swapping the `@riverpod aiProvider` factory, nothing else.

**OCR pipeline**: `OcrService` is also abstracted. The ML Kit implementation handles most real-world receipts. For higher accuracy, drop in a cloud OCR (Google Document AI, AWS Textract) by implementing the same interface.

**Expense + Receipt split**: Receipts hold the raw scan data (image, OCR text, items). Expenses are the financial record derived from a receipt. This lets you query expenses independently for analytics without touching the receipt documents.

**Riverpod stream providers**: Dashboard and receipt list use `StreamProvider` backed by Firestore snapshots, so the UI updates in real-time when a receipt finishes processing.

**Fallback classification**: When Ollama is unavailable, the service falls back to keyword-based classification. Users get a result even offline.
