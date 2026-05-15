# FINPRO-GROUP5-MBD

## Smart Door Lock with Multi-Mode Access

Smart Door Lock with Multi-Mode Access adalah sistem kunci pintu berbasis Arduino yang menyediakan mekanisme keamanan melalui autentikasi password menggunakan keypad sebagai input dan juga didukung oleh komunikasi serial untuk logging dan monitoring sistem.

Sistem ini memiliki 3 mode operasi yaitu **Locked**, **Unlocked**, dan **Alarm**, yang dikendalikan oleh logika program dengan memanfaatkan timer, interrupt, dan pengolahan data. Ketika password dimasukkan dengan benar melalui keypad, kunci akan terbuka (menggerakkan servo sebagai dummy pintu) dan kembali terkunci otomatis setelah beberapa waktu, sementara percobaan gagal berulang akan mengaktifkan alarm berupa buzzer dan indikator LED. Tombol darurat memungkinkan akses langsung melalui interrupt untuk kondisi tertentu.

---

## Anggota Kelompok 5

Berikut adalah anggota tim Finpro MBD - Group 5:

| No | Nama | NPM | Peran / Fokus |
|---|---|---|---|
| 1 | **Muhammad Zaki Alkhairi** | - | ... |
| 2 | **Muhammad Hashif Jade** | 2406396786 | ... |
| 3 | **Naziehan Labieb** | - | ... |
| 4 | **Toriq Fathoni Dezi** | - | ... |

---

## Fitur Utama

- **Autentikasi Multi-Mode:** Manajemen 3 status utama sistem (`Locked`, `Unlocked`, `Alarm`) secara real-time.
- **Input Keypad 4x4:** Antarmuka input password yang responsif untuk membuka akses penguncian.
- **Mekanisme Auto-Lock (Timer):** Penguncian kembali secara otomatis menggunakan kalkulasi waktu berbasis timer internal setelah pintu terbuka.
- **Sistem Keamanan & Alarm:** Deteksi *brute-force* (salah password berulang) yang otomatis memicu buzzer dan LED indikator.
- **Tombol Darurat (External Interrupt):** Fitur *bypass* instan menggunakan pin interrupt eksternal untuk membuka kunci dalam kondisi darurat.
- **Serial Logging:** Monitoring status sistem, input, dan error handling melalui Serial Communication.

---
