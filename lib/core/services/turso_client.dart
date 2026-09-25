import 'package:dio/dio.dart';

/// Minimal Turso (libSQL) HTTP client.
///
/// Talks directly to the Turso platform API (`/v2/pipeline`) with a platform
/// JWT — no local native libsql bindings and no intermediate backend needed,
/// which keeps the app self-contained on every platform (mobile, desktop, web).
///
/// Used by [AccountService] for the built-in auth: users, favourites and
/// playlists live in the Turso database.
class TursoClient {
  final String url;
  final String authToken;
  final Dio _dio;

  TursoClient({
    required this.url,
    required this.authToken,
  }) : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 25),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
          },
        ));
}

/// Result of a single SQL statement.
///
/// * [rows] — objects keyed by column name.
/// * [rowsAffected] — number of changed rows for writes.
/// * [lastInsertId] — rowid of the last insert, when applicable.
class TursoResult {
  final List<Map<String, dynamic>> rows;
  final int rowsAffected;
  final int? lastInsertId;

  const TursoResult({
    this.rows = const [],
    this.rowsAffected = 0,
    this.lastInsertId,
  });

  dynamic firstValue(String column) =>
      rows.isEmpty ? null : rows.first[column];
}

class TursoException implements Exception {
  final String message;
  TursoException(this.message);

  @override
  String toString() => message;
}

/// Base URL for the platform libSQL HTTP API from a `libsql://` database URL.
String tursoApiUrl(String dbUrl) {
  var host = dbUrl.trim();
  if (host.startsWith('libsql://')) host = host.substring('libsql://'.length);
  if (host.endsWith('/')) host = host.substring(0, host.length - 1);
  return 'https://$host/v2/pipeline';
}

/// Extracts a Dart value from a libSQL pipeline cell (value objects like
/// `{'type': 'integer', 'value': '3'}`).
dynamic _cellToValue(dynamic cell) {
  if (cell is Map) {
    if (cell['value'] != null) return cell['value'];
    return null;
  }
  return cell;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// Executes a list of SQL statements in one HTTP round-trip and returns one
/// [TursoResult] per statement.
Future<List<TursoResult>> tursoExecute(
  TursoClient client,
  List<({String sql, List<dynamic> args})> statements,
) async {
  if (statements.isEmpty) return const [];

  final body = {
    'requests': [
      for (final s in statements)
        {
          'type': 'execute',
          'stmt': {
            'sql': s.sql,
            'args': [for (final a in s.args) _argToHrana(a)],
          },
        },
      {'type': 'close'},
    ],
  };

  final Response res;
  try {
    res = await _post(client, body);
  } on TursoException {
    rethrow;
  } catch (e) {
    throw TursoException('No se pudo conectar a la base de datos: $e');
  }

  final results = <TursoResult>[];
  final raw = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
  final resultsList = raw['results'] is List ? List<dynamic>.from(raw['results']) : const [];

  for (final item in resultsList) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);

    if (m['type'] == 'error' || m['error'] is Map) {
      final err = m['error'] is Map ? Map<String, dynamic>.from(m['error']) : m;
      throw TursoException('Error de base de datos: ${err['message'] ?? err}');
    }

    final r = m['response'] is Map ? Map<String, dynamic>.from(m['response']) : null;
    final result = r == null || r['result'] is! Map
        ? const TursoResult()
        : _parseResult(Map<String, dynamic>.from(r['result'] as Map));
    results.add(result);
  }

  // Pipeline responses only include entries for execute requests.
  final needed = statements.length;
  while (results.length < needed) {
    results.add(const TursoResult());
  }
  return results.sublist(0, needed);
}

Future<TursoResult> tursoExecuteOne(
  TursoClient client,
  String sql,
  List<dynamic> args,
) async {
  final results = await tursoExecute(client, [(sql: sql, args: args)]);
  return results.first;
}

TursoResult _parseResult(Map<String, dynamic> result) {
  final cols = result['cols'] is List ? List<dynamic>.from(result['cols']) : const [];
  final columnNames = cols
      .map((c) => (c is Map ? c['name']?.toString() : c?.toString()) ?? '')
      .toList();

  final rows = <Map<String, dynamic>>[];
  if (result['rows'] is List) {
    for (final rawRow in List<dynamic>.from(result['rows'])) {
      if (rawRow is! List) continue;
      final row = <String, dynamic>{};
      for (var i = 0; i < rawRow.length && i < columnNames.length; i++) {
        row[columnNames[i]] = _cellToValue(rawRow[i]);
      }
      rows.add(row);
    }
  }

  return TursoResult(
    rows: rows,
    rowsAffected: _toInt(result['affected_row_count']) ?? 0,
    lastInsertId: _toInt(result['last_insert_rowid']),
  );
}

Future<Response<dynamic>> _post(TursoClient client, Map<String, dynamic> body) {
  return client._dio.post(tursoApiUrl(client.url), data: body);
}

/// Encodes a Dart value as a Hrana v2 arg.
///
/// Quirks verified against the Turso platform API:
/// * `integer` values must be JSON **strings** — a JSON number fails with
///   400 "invalid type: integer `5`, expected a borrowed string".
/// * `real` values are JSON numbers.
/// * `null` takes no value field.
Map<String, dynamic> _argToHrana(dynamic v) {
  if (v == null) return {'type': 'null'};
  if (v is int) return {'type': 'integer', 'value': v.toString()};
  if (v is bool) return {'type': 'integer', 'value': v ? '1' : '0'};
  if (v is num) return {'type': 'real', 'value': v};
  if (v is DateTime) return {'type': 'text', 'value': v.toIso8601String()};
  return {'type': 'text', 'value': v.toString()};
}
