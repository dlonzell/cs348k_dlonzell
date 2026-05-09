# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RoleplAR is an iOS/Vision Pro experiential language learning application that generates immersive role-playing scenarios for language practice (currently Japanese). Users practice speaking with AI characters in 3D scenes with real-time support and feedback.

## Build & Test Commands

```bash
# Build the project
xcodebuild -scheme RoleplAR build

# Run all tests
xcodebuild test -scheme RoleplAR

# Run specific test target
xcodebuild test -scheme RoleplAR -only-testing:FuriganaTests
```

Requires Xcode 15.3+ with iOS 16+ SDK. The project uses Swift Package Manager for dependencies (packages resolve automatically on build).

## Architecture

### Core Components

1. **NarrativeModel** (`NarrativeModel.swift`) - Central state management for scenarios, scenes, and learning goals. Handles scene generation via OpenAI and tracks progression.

2. **DialogueViewModel** (`DialogueViewModel.swift`) - Manages real-time conversation with speech recognition/synthesis. Handles three message streams: main dialogue, support messages, and callout tracking.

3. **OpenAIService** (`OpenAIService.swift`) - API integration layer for all OpenAI calls including scenario generation, dialogue responses, and support features.

4. **SceneView** (`SceneView.swift`) - RealityKit-based 3D rendering for immersive AR experience with character and background images.

5. **Support System** (`SupportView.swift`) - Contextual help during conversations: translations, suggestions, and corrective feedback.

6. **Furigana** (`Furigana.swift`) - Japanese text annotation using MeCab morphological analyzer to add reading guides to kanji.

### Data Flow

1. User inputs learning goals (vocabulary, grammar, tasks) in `MainMenuView`
2. `NarrativeModel` generates scenario with characters/scenes via OpenAI
3. `SceneView` renders 3D environment; `DialogueViewModel` handles conversation
4. Support system analyzes utterances and provides help in parallel
5. All interactions logged to Supabase via `Database.swift`

### Key Data Models

- **Scene**: Contains situation, character info, images, learning goals, and message arrays
- **LearningGoals**: Vocabulary, grammar patterns, and tasks for a session
- **Message**: Has messageType (mainDialogue, supportTranslation, supportSuggestion, supportFeedback, callout), content, and role

### Window Structure

The app manages 3 windows (see `RoleplARApp.swift`):
- Main menu for setup
- Dialogue window for conversation
- Immersive scene window for 3D rendering

## Key Dependencies

| Package | Purpose |
|---------|---------|
| OpenAI / XCAOpenAIClient | AI API integration |
| Supabase | Backend database |
| Mecab-Swift / IPADic | Japanese morphological analysis |
| RealityKit | 3D scene rendering |

## Development Notes

- **Debug Mode**: Set `DEBUG_MODE` in `MainMenuView.swift` to skip image generation for faster iteration
- **Language**: Currently hardcoded for Japanese in `Constants.swift`
- **Prompts**: System prompts for AI behavior are defined in `Constants.swift`
- **API Keys**: Stored in `Constants.swift` and `Database.swift` (should be moved to environment variables for production)
