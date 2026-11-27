# Benz Mirror: aset ikon

| Folder | Isi | Dipakai untuk |
|---|---|---|
| 01-IconComposer-Layers | SVG 1024 x 1024, persegi, tanpa mask, datar | Sumber ikon asli di Icon Composer |
| 02-SVG-Flat | Ikon utuh: persegi dan bersudut bulat | Web, dokumen, presentasi |
| 03-Mark | Logo Beny: hitam, putih, ink, dan dua bagiannya | Aset brand |
| 04-Xcode | Assets.xcassets: AppIcon, BenyMark, MenuBarIcon | Ditambahkan ke project Xcode |
| 05-PNG-Concept | Render kaca 3D 1024 px (A, B, C) | Referensi tampilan dan materi promosi |
| 06-PNG-Pieces | PNG 1024 px per layer: flat dan glass | Disusun ulang di Figma atau editor gambar |

## Ikon aplikasi: pilih satu cara

**Cara 1, disarankan (ikon berlapis):**
1. Buka Icon Composer, buat file baru bernama AppIcon.
2. Background: isi gradien sesuai tabel di bawah, atau impor SVG dari `background/`.
3. Foreground: impor `mark-1-left.svg` dan `mark-2-right.svg` sebagai dua layer.
4. Atur specular, translucency, dan shadow di Icon Composer.
5. Cek tampilan default, dark, mono, serta ukuran 16 dan 32 px.
6. Tambahkan file `.icon` ke project, lalu HAPUS `AppIcon.appiconset` agar namanya tidak bentrok.

**Cara 2 (bitmap):** pakai `AppIcon.appiconset` apa adanya. Tampilannya sama dengan render A,
tetapi efeknya statis dan sistem bisa mengolahnya lagi. Uji di Mac sebelum rilis.

## Warna

| Varian | Atas | Bawah | Logo |
|---|---|---|---|
| A dark blue | #020a1c | #0a55c8 | #ffffff |
| B clear blue | #5cc2ff | #004fd0 | #ffffff |
| C light | #fcfdff | #d2dbe8 | #0b1424 |

## Memakai di SwiftUI

```swift
Image("BenyMark").resizable().scaledToFit().frame(height: 28)   // mengikuti foregroundStyle

MenuBarExtra("Benz Mirror", image: "MenuBarIcon") { MenuContent() }
```
`MenuContent` adalah view menu buatan Anda sendiri.

Render kaca 3D adalah gambar raster, jadi tidak ada versi SVG-nya. SVG di paket ini datar,
dan efek kaca ditambahkan oleh Icon Composer. Paket ini belum diuji di Xcode.

## Potongan PNG (06-PNG-Pieces)

- Semua berukuran 1024 x 1024. Di dalam satu set posisinya pas, jadi tinggal ditumpuk di titik 0,0.
  Jangan campur `flat/` dengan `glass/`: ukuran logonya beda (versi glass lebih kecil).
- `glass/`: urutan dari bawah `1-background`, `2-shadow`, `3-mark-glass`. Pakai satu mark gabungan,
  atau pasangan `left` dan `right`.
- Pantulan pada mark glass dibuat untuk background variannya. Jangan ditukar antarvarian.
- `flat/`: logo transparan dan background polos. Untuk Icon Composer, pakai yang flat (atau SVG), bukan glass.
