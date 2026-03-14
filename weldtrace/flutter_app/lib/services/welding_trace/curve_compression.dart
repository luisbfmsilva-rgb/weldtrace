import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Utility class for compressing and decompressing weld trace curve data.
///
/// Uses gzip compression to reduce storage requirements for large weld curves.
/// A 5 000-sample curve (≈ 400 kB JSON) compresses to roughly 30–60 kB.
///
/// Usage:
/// ```dart
/// // Compress before saving to DB
/// final compressed = CurveCompression.compressCurve(jsonString);
///
/// // Decompress when loading from DB
/// final json = CurveCompression.decompressCurve(compressedBytes);
/// ```
class CurveCompression {
  CurveCompression._();

  /// Compresses a JSON-encoded curve string using gzip.
  ///
  /// [json] — JSON string (e.g. the output of `jsonEncode(curve.map(...).toList())`)
  ///
  /// Returns the compressed bytes as a [Uint8List] ready to be stored in a
  /// BLOB column.
  static Uint8List compressCurve(String json) {
    final bytes      = utf8.encode(json);
    final compressed = gzip.encode(bytes);
    return Uint8List.fromList(compressed);
  }

  /// Decompresses gzip bytes back to a JSON string.
  ///
  /// [data] — the [Uint8List] previously produced by [compressCurve].
  ///
  /// Returns the original JSON string, which can be decoded with `jsonDecode`.
  static String decompressCurve(Uint8List data) {
    final decompressed = gzip.decode(data);
    return utf8.decode(decompressed);
  }
}
