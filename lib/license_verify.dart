// Verifikasi lisensi offline di Flutter — mirror dari licensing/keygen.py.
// Format: v1.<APP>.<TIER>.<EXP>.<RAND>.<SIG>
// SIG = HMAC_SHA256(secret, "v1.APP.TIER.EXP.RAND") hex upper [:8]
// Butuh dependency: crypto: ^3.0.3  +  shared_preferences
//
// Trial: LicenseStore menangani first_run + free quota soal/hari.
// Secret asli diisi saat build via --dart-define=NATIVE_SECRET=...
// JANGAN hardcode secret produksi di repo. Default di bawah hanya untuk dev.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LicenseConfig {
  // Diisi via: flutter build apk --dart-define=NATIVE_SECRET=...
  static const String secret = String.fromEnvironment(
    'NATIVE_SECRET',
    defaultValue: 'dev-secret-ganti-saat-build-min16char',
  );
  static const int trialDays = 7;
  static const int freeSoalPerHari = 3;
}

class LicenseResult {
  final bool valid;
  final String message;
  final String app; // MATH|FIS|BDL
  final String tier; // PRO|LIFETIME|TRIAL|FREE
  final String exp; // YYYYMMDD
  const LicenseResult(this.valid, this.message,
      {this.app = '', this.tier = 'FREE', this.exp = ''});
}

String _sig(String secret, String app, String tier, String exp, String rand) {
  final msg = utf8.encode('v1.$app.$tier.$exp.$rand');
  final d = Hmac(sha256, utf8.encode(secret)).convert(msg);
  return d.toString().toUpperCase().substring(0, 8);
}

LicenseResult verifyKey(String rawKey, {String expectedApp = ''}) {
  final key = rawKey.trim().toUpperCase();
  final p = key.split('.');
  if (p.length != 6 || p[0] != 'V1') {
    return const LicenseResult(false, 'Format salah. Contoh: v1.MATH.PRO.20270922.7KQ29X.9F2D8A1B');
  }
  final app = p[1], tier = p[2], exp = p[3], rand = p[4], sig = p[5];
  const apps = {'MATH', 'FIS', 'BDL'};
  if (!apps.contains(app)) return const LicenseResult(false, 'Kode app tidak dikenal.');
  if (tier != 'PRO' && tier != 'LIFETIME') {
    return const LicenseResult(false, 'Tier tidak dikenal.');
  }
  if (exp.length != 8 || int.tryParse(exp) == null) {
    return const LicenseResult(false, 'Tanggal exp tidak valid.');
  }
  final want = _sig(LicenseConfig.secret, app, tier, exp, rand);
  if (want != sig) return const LicenseResult(false, 'Signature tidak cocok.');
  if (tier != 'LIFETIME') {
    try {
      final d = DateTime(int.parse(exp.substring(0, 4)),
          int.parse(exp.substring(4, 6)), int.parse(exp.substring(6, 8)));
      if (d.isBefore(DateTime.now())) {
        return const LicenseResult(false, 'Key expired ${d.toIso8601String().substring(0, 10)}.');
      }
    } catch (_) {
      return const LicenseResult(false, 'Tanggal exp tidak valid.');
    }
  }
  if (expectedApp.isNotEmpty && app != 'BDL' && app != expectedApp) {
    return LicenseResult(false, 'Key $app tidak berlaku untuk $expectedApp.');
  }
  final label = tier == 'LIFETIME'
      ? 'LIFETIME'
      : 's/d ${exp.substring(0, 4)}-${exp.substring(4, 6)}-${exp.substring(6, 8)}';
  return LicenseResult(true, 'VALID $app/$tier $label.',
      app: app, tier: tier, exp: exp);
}

class LicenseStore {
  static const _kKey = 'native_license_key';
  static const _kFirst = 'native_first_run';
  static const _kSoalDay = 'native_soal_day';
  static const _kSoalCount = 'native_soal_count';

  final String appId; // MATH | FIS
  LicenseStore(this.appId);

  Future<void> ensureFirstRun() async {
    final sp = await SharedPreferences.getInstance();
    if (!sp.containsKey(_kFirst)) {
      await sp.setString(_kFirst, DateTime.now().toIso8601String());
    }
  }

  Future<int> trialLeftDays() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kFirst);
    if (s == null) return LicenseConfig.trialDays;
    final first = DateTime.tryParse(s) ?? DateTime.now();
    final used = DateTime.now().difference(first).inDays;
    final left = LicenseConfig.trialDays - used;
    return left < 0 ? 0 : left;
  }

  Future<bool> isTrialActive() async => (await trialLeftDays()) > 0;

  Future<LicenseResult?> savedKey() async {
    final sp = await SharedPreferences.getInstance();
    final k = sp.getString(_kKey);
    if (k == null || k.isEmpty) return null;
    final r = verifyKey(k, expectedApp: appId);
    return r.valid ? r : null;
  }

  Future<LicenseResult> saveKey(String key) async {
    final r = verifyKey(key, expectedApp: appId);
    if (!r.valid) return r;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, key.trim().toUpperCase());
    return r;
  }

  Future<void> clearKey() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kKey);
  }

  /// status gabungan: PRO jika key valid ATAU trial aktif, else FREE
  Future<(String tier, String note)> status() async {
    await ensureFirstRun();
    final k = await savedKey();
    if (k != null) return (k.tier, k.message);
    if (await isTrialActive()) {
      final left = await trialLeftDays();
      return ('TRIAL', 'Trial tersisa $left hari. Aktivasi key untuk PRO.');
    }
    return ('FREE', 'Mode gratis: teori terbuka, soal 3/hari.');
  }

  /// quota soal harian untuk FREE (PRO/TRIAL unlimited)
  Future<bool> canOpenSoal() async {
    final s = await status();
    if (s.$1 == 'PRO' || s.$1 == 'LIFETIME' || s.$1 == 'TRIAL') return true;
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final day = sp.getString(_kSoalDay) ?? '';
    var n = sp.getInt(_kSoalCount) ?? 0;
    if (day != today) {
      await sp.setString(_kSoalDay, today);
      await sp.setInt(_kSoalCount, 1);
      return true;
    }
    if (n >= LicenseConfig.freeSoalPerHari) return false;
    await sp.setInt(_kSoalCount, n + 1);
    return true;
  }
}
