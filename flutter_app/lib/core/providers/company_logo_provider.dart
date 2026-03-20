import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the manager's company logo stored on-device.
///
/// The logo is persisted as a PNG file in the app's documents directory.
/// Its path is stored in SharedPreferences under [_prefKey].
///
/// The logo bytes are exposed as [AsyncValue<Uint8List?>]:
///   - `null`      → no logo configured
///   - `Uint8List` → logo bytes ready to embed in PDF
class CompanyLogoNotifier extends StateNotifier<AsyncValue<Uint8List?>> {
  CompanyLogoNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  static const _prefKey = 'company_logo_path';
  static const _fileName = 'company_logo.png';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path  = prefs.getString(_prefKey);
      if (path == null) {
        state = const AsyncValue.data(null);
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        state = const AsyncValue.data(null);
        return;
      }
      final bytes = await file.readAsBytes();
      state = AsyncValue.data(bytes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Prompt the user to pick an image and save it as the company logo.
  Future<void> pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth:  512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      await _saveLogo(bytes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Remove the stored company logo.
  Future<void> removeLogo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path  = prefs.getString(_prefKey);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      await prefs.remove(_prefKey);
      state = const AsyncValue.data(null);
    } catch (_) {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _saveLogo(Uint8List bytes) async {
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.writeAsBytes(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, file.path);
    state = AsyncValue.data(bytes);
  }
}

final companyLogoProvider =
    StateNotifierProvider<CompanyLogoNotifier, AsyncValue<Uint8List?>>(
  (ref) => CompanyLogoNotifier(),
);
