# Fisika Native — Flutter (offline, UI ala Obsidian)
# App mandiri: TIDAK butuh install Obsidian. Konten dari vault di-export ke assets/content/content.json.

## Dev lokal (butuh Flutter SDK sekali saja)
flutter pub get
flutter run --dart-define=NATIVE_SECRET=dev-secret-ganti-saat-build-min16char

## Build APK release (di laptop yg ada SDK)
flutter build apk --release --dart-define=NATIVE_SECRET="$env:NATIVE_MASTER_SECRET"
# hasil: build/app/outputs/flutter-apk/app-release.apk

## Build via GitHub Actions (tanpa SDK lokal — RECOMMENDED)
1. Repo ini sudah live di github.com/jarlelauch/physics-native
2. Tambahkan workflow via web (sekali saja, karena token CLI tanpa scope workflow):
   repo → Add file → Create new file → path `.github/workflows/build-apk.yml` →
   paste isi `ci/build-apk.yml` → Commit.
   (Alternatif: `gh auth refresh -s workflow` di terminal kamu, lalu push folder `.github/`.)
3. Repo Settings → Secrets and variables → Actions → New repository secret:
   Name `NATIVE_SECRET`, isi = master secret (32+ char, SAMA dengan yang dipakai generate key).
4. Tiap push ke main / tiap Release → APK otomatis di Actions → download dari Artifacts / Releases.

## Ganti konten dari vault
python ../../release/prepare_vault_release.py --vault "C:/Users/realh/physics-native-vault" --app FIS --out "assets/content"
flutter pub get

## Lisensi
Freemium + trial 7 hari + key PRO offline (lihat ../../licensing/license_spec.md).
Generate key: python ../../licensing/keygen.py generate --app FIS --tier PRO --exp 2027-09-22 --uid nama01
