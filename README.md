# FINPRO-GROUP5-MBD - Smart Door Lock with Multi-Mode Access

---

## Anggota Kelompok 5
| No | Nama | NPM | Peran / Fokus |
|---|---|---|---|
| 1 | **Muhammad Zaki Alkhairi** | 2406432375 | ... |
| 2 | **Muhammad Hashif Jade** | 2406396786 | ... |
| 3 | **Naziehan Labieb** | 2406487102 | ... |
| 4 | **Toriq Fathoni Dezi** | 2406487115 | ... |

---

## 1. Introduction to the problem and the solution

### The Problem
Keamanan akses ruangan konvensional yang mengandalkan kunci fisik memiliki berbagai kelemahan, mulai dari risiko kunci hilang, mudah digandakan, hingga sulitnya memantau histori akses secara terpusat. Selain itu, sistem penguncian manual tidak memiliki mekanisme pertahanan aktif apabila terjadi upaya pembobolan atau akses paksa secara berulang.

### The Solution
Proyek ini mengimplementasikan **Smart Door Lock with Multi-Mode Access** berbasis Arduino (ATmega328P) sebagai solusi sistem penguncian digital yang aman, interaktif, dan responsif. Sistem ini menggunakan autentikasi password melalui keypad serta dilengkapi dengan sistem kendali status (*state management*) yang ketat. Kunci digital ini mengintegrasikan fungsi penguncian otomatis, indikator alarm pertahanan terhadap *brute-force*, serta tombol darurat fisik untuk memastikan keamanan sekaligus kemudahan akses pengguna.

---

## 2. Hardware design and implementation details

Sistem ini mengintegrasikan komponen input, proses, dan output yang saling terhubung untuk membangun subsistem keamanan yang utuh:

- **Microcontroller:** Arduino Uno (ATmega328P) sebagai unit pemroses utama.
- **Input Devices:**
  - **Keypad 4x4:** Digunakan sebagai antarmuka utama pengguna untuk memasukkan kombinasi password.
  - **Push Button:** Dikonfigurasikan sebagai *Emergency Switch* yang terhubung ke pin Interrupt eksternal.
- **Output Devices:**
  - **Servo Motor:** Berfungsi sebagai *dummy* dari mekanisme fisik slot kunci pintu.
  - **Buzzer:** Komponen audio untuk menghasilkan bunyi peringatan (alarm).
  - **LED Indikator:** LED Merah dan Hijau untuk merepresentasikan status visual dari sistem penguncian.
- **Communication:** Jalur komunikasi serial (UART) ke PC untuk keperluan *logging* data secara *real-time*.

---

## 3. Software implementation details

Arsitektur perangkat lunak dibangun di atas ekosistem Arduino dengan memanfaatkan fitur-fitur tingkat rendah dari mikrokontroler untuk menjamin performa yang *real-time*:

- **Multi-Mode State Machine:** Logika program mengendalikan 3 mode operasi utama:
  1. `Locked`: Mode siaga di mana pintu terkunci, LED merah menyala, dan sistem menunggu input keypad.
  2. `Unlocked`: Mode akses terbuka setelah password benar, ditandai dengan pergerakan servo dan LED hijau menyala.
  3. `Alarm`: Mode proteksi aktif yang terpicu apabila terjadi kesalahan input password secara berulang.
- **Timer & Auto-Lock:** Memanfaatkan manajemen waktu (*timing logic*) untuk menghitung durasi mode `Unlocked` sebelum memicu modul servo agar kembali ke posisi `Locked` secara otomatis.
- **External Interrupt Handling:** Menggunakan interupsi eksternal pada pin hardware untuk membaca *Push Button* darurat. Mekanisme ini memastikan sistem langsung berpindah ke mode akses tertentu secara instan tanpa tertahan oleh proses *looping* utama.
- **Serial Communication Logging:** Mengirimkan data status sistem, *log* percobaan input, serta indikasi *error* ke Serial Monitor untuk keperluan monitoring eksternal.

---

## 4. Test results and performance evaluation

...

---

## 5. Conclusion and future work

### Conclusion
...

### Future Work
...
