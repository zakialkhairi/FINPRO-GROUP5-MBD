# FINPRO GROUP5 MBD - Smart Door Lock with Multi-Mode Access

---

## Anggota Kelompok 5
| No | Nama | NPM | Peran / Fokus |
|---|---|---|---|
| 1 | **Muhammad Zaki Alkhairi** | 2406432375 | Membuat dokumentasi dan presentasi proyek. |
| 2 | **Muhammad Hashif Jade** | 2406396786 | Membuat penyusunan laporan proyek, dokumentasi dan presentasi proyek. |
| 3 | **Naziehan Labieb** | 2406487102 | Membuat program dan logika sistem, Membuat rangkaian di Wokwi, Membuat rangkaian fisik. |
| 4 | **Toriq Fathoni Dezi** | 2406487115 | Membuat program dan logika sistem, Membuat rangkaian fisik. |

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
  - **LCD I2C:** Digunakan untuk menampilkan status sistem dan instruksi kepada pengguna secara real-time.
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

Pengujian sistem dilakukan untuk memastikan seluruh komponen dan fitur dapat berjalan sesuai dengan rancangan. Pengujian meliputi input password melalui keypad, tampilan status pada LCD I2C, pergerakan servo motor, indikator LED, buzzer alarm, serta fungsi tombol darurat berbasis interrupt. Sistem diuji pada beberapa kondisi seperti password benar, password salah, dan penggunaan emergency button.

Hasil pengujian menunjukkan bahwa sistem mampu menjalankan seluruh fungsi utama dengan baik. Pada kondisi awal, LED merah menyala untuk menandakan bahwa pintu berada dalam mode `Locked`. Ketika password yang benar dimasukkan, servo bergerak membuka kunci pintu dan LED hijau menyala sebagai indikator akses berhasil. Setelah beberapa detik, sistem kembali ke mode `Locked` secara otomatis menggunakan mekanisme timer.

Selain itu, ketika password salah dimasukkan beberapa kali secara berturut-turut, buzzer alarm aktif sebagai bentuk proteksi terhadap percobaan akses ilegal. LCD I2C berhasil menampilkan informasi status sistem secara real-time seperti instruksi memasukkan password dan status akses. Push button darurat juga dapat menjalankan fungsi interrupt dengan baik sehingga sistem mampu memberikan akses langsung secara cepat tanpa terganggu proses utama pada program.

Secara keseluruhan, performa sistem berjalan stabil baik pada simulasi Wokwi maupun implementasi hardware fisik. Integrasi antara hardware dan software berhasil dilakukan dengan baik sehingga sistem mampu menjalankan autentikasi, kontrol akses pintu, alarm keamanan, dan monitoring sistem sesuai tujuan proyek.

---

## 5. Conclusion and future work

### Conclusion
Proyek **Smart Door Lock with Multi-Mode Access** berhasil dirancang dan diimplementasikan menggunakan Arduino Uno sebagai pengendali utama sistem. Sistem mampu menjalankan autentikasi password melalui keypad, mengontrol akses pintu menggunakan servo motor, serta memberikan indikator keamanan menggunakan LED dan buzzer. Selain itu, penerapan konsep timer dan interrupt berhasil mendukung fitur otomatisasi dan akses darurat pada sistem keamanan pintu.

Implementasi sistem menunjukkan bahwa konsep Embedded System dapat diterapkan secara efektif pada aplikasi keamanan sederhana berbasis mikrokontroler. Integrasi antara hardware dan software juga berhasil dilakukan dengan baik sehingga seluruh fitur utama sistem dapat berjalan sesuai dengan perancangan dan kebutuhan pengguna.

### Future Work
Beberapa pengembangan yang dapat dilakukan pada proyek ini di masa mendatang antara lain:

- Menambahkan teknologi RFID atau sensor sidik jari sebagai metode autentikasi tambahan.
- Mengintegrasikan sistem dengan IoT agar dapat dimonitor dan dikontrol melalui smartphone.
- Menambahkan database penyimpanan histori akses pengguna.
- Menggunakan solenoid door lock agar mekanisme penguncian lebih realistis.
- Menambahkan sistem backup power untuk menjaga sistem tetap aktif saat listrik mati.

