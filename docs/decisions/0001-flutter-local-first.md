# ADR 0001: Flutter Local-First App

## Context

The product brief requires an Android-first SMS tracker with native SMS capture and
a cross-platform application layer.

## Decision

Use Flutter for the app layer, Kotlin for Android SMS/background integrations, and
encrypted SQLite through drift/SQLCipher for local persistence.

## Consequences

All product behavior must work offline. Native Android code owns SMS access; Dart
owns parsing, enrichment, persistence orchestration, and UI.
