/// Single-Engine Hive Routing
///
/// `hive_ce` is an exact API-compatible fork of `hive` (same `Box`,
/// `Hive.initFlutter()`, `Hive.openBox()` surface), actively maintained,
/// and Wasm-compatible. We use it on BOTH native and web to keep the
/// persistence layer single-sourced and avoid the legacy two-package
/// conflict.
///
/// Native: `hive_native.dart` → `hive_ce_flutter`
/// Web:    `hive_web.dart` → `hive_ce_flutter`
library;

export 'hive_web.dart' if (dart.library.io) 'hive_native.dart';
