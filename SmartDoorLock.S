; Smart Door Lock
; Device:   Arduino UNO / ATmega328P
; Fitur:    LCD I2C, Keypad 4x4, Servo, LED, Buzzer, Reset Darurat, Serial Debug
; Program utama untuk mengendalikan sistem pengaman pintu menggunakan input kata sandi berbasis bahasa Assembly AVR.
#define __SFR_OFFSET 0
#include <avr/io.h>
#include <avr/interrupt.h>

.text
.global main

; KONFIGURASI KATA SANDI / PASSWORD
; Kata sandi utama: "1593"
; Disimpan berupa representasi karakter ASCII, bukan dalam desimal/biner.

#define PWD_LEN  4
#define PWD_0    '1'
#define PWD_1    '5'
#define PWD_2    '9'
#define PWD_3    '3'

; KONFIGURASI LCD I2C
; 0x4E adalah instruksi write/tulis ke alamat modul I2C ekspander PCF8574
; (alamat dasar I2C 0x27 yang digeser ke kiri sejauh 1 bit untuk modus R/W).
#define LCD_ADDR_W    0x4E  
#define LCD_BACKLIGHT 0x08
#define LCD_EN        0x04
#define LCD_RS        0x01

#define TEMPLOCK_OVF_HI  0x01
#define TEMPLOCK_OVF_LO  0x31

; ALOKASI MEMORI SRAM
; 0x0100 : Buffer masukan kata sandi (4 byte)
; 0x0106 : Register pencacah Timer0 Overflow High (OVF_CNT_H)
; 0x0107 : Register pencacah Timer0 Overflow Low (OVF_CNT_L)
.set INPUT_BUF,  0x0100    
.set OVF_CNT_H,  0x0106    
.set OVF_CNT_L,  0x0107    

main:
    ; Inisialisasi Stack Pointer (SP)
    ; Alamat tumpukan harus menunjuk akhir lokasi memori alamat (RAMEND),
    ; memastikan perintah rcall, ret, push, dan pop berjalan stabil.
    ldi  r16, hi8(RAMEND)
    out  SPH, r16
    ldi  r16, lo8(RAMEND)
    out  SPL, r16
    clr  r1

    ; Inisialisasi Port D
    ; PD2     : PIN masukan Tombol Reset dengan Pull-up Internal.
    ; PD3     : PIN keluaran Buzzer.
    ; PD4-PD7 : PIN masukan Kolom Keypad (Input Pull-up).
    ldi  r16, 0x08          ; Atur PD3 sebagai Output
    out  DDRD, r16
    ldi  r16, 0xF4          ; Aktifkan Pull-up di PD4-PD7 dan PD2
    out  PORTD, r16

    ; Inisialisasi Port C
    ; PC0-PC3 : PIN keluaran Baris Keypad.
    ; PC4     : PIN antarmuka I2C SDA (ke LCD).
    ; PC5     : PIN antarmuka I2C SCL (ke LCD).
    ldi  r16, 0x0F          ; Atur PC0-PC3 sebagai Output
    out  DDRC, r16
    ldi  r16, 0x3F          ; Keadaan awal memicu Baris Keypad HIGH, I2C Pull-up
    out  PORTC, r16

    ; Inisialisasi Port B
    ; PB1 / D9  : PIN keluaran Motor Servo (Sinyal PWM OC1A).
    ; PB2 / D10 : PIN keluaran LED Merah (Terkunci).
    ; PB3 / D11 : PIN keluaran LED Hijau (Terbuka).
    ldi  r16, 0x0E          ; Atur PB1, PB2, PB3 sebagai Output
    out  DDRB, r16
    ldi  r16, 0x00
    out  PORTB, r16

    ; Mengaktifkan LED Merah sebagai tanda mesin masuk fase awal (terkunci)
    sbi  PORTB, 2

    ; Inisialisasi Interupsi Eksternal (EXTINT0)
    ; Memanfaatkan INT0. Karena memanfaatkan mode pull-up (HIGH saat diam), 
    ; interupsi diset aktif saat terjadi Fall Edge (sinyal perubahan HIGH ke LOW).
    ldi  r16, (1<<ISC01)
    sts  EICRA, r16
    ldi  r16, (1<<INT0)
    out  EIMSK, r16

    ; Konfigurasi Timer1 untuk kendali Servo Motor
    ; Berjalan dalam modus Fast PWM dengan pemicu TOP dari ICR1.
    ; Memiliki Prescaler sebesar 8, ICR1 diset pada limit nilai 39999 (Periode kisaran 20ms).
    ldi  r16, (1<<WGM11) | (1<<COM1A1)
    sts  TCCR1A, r16
    ldi  r16, (1<<WGM13) | (1<<WGM12) | (1<<CS11)
    sts  TCCR1B, r16
    ldi  r16, hi8(39999)
    sts  ICR1H, r16
    ldi  r16, lo8(39999)
    sts  ICR1L, r16

    ; Konfigurasi Timer2 untuk output suara (Buzzer)
    ; Dikembalikan mode PWM non-aktif di tahap inisialisasi dasar.
    sts  TCCR2A, r1
    sts  TCCR2B, r1

    ; Konfigurasi Timer0 untuk kalkulasi jeda durasi penguncian darurat waktu tunggu.
    ; Fase Timer tetap dalam keadaan berhenti selama prosedur start_templock_timer belum dipanggil.
    out  TCCR0A, r1
    out  TCCR0B, r1
    ldi  r16, (1<<TOIE0)    
    sts  TIMSK0, r16

    ; Konfigurasi awal protokol I2C / TWI untuk transmisi data Modul LCD.
    ldi  r16, 72
    sts  TWBR, r16
    sts  TWSR, r1          
    ldi  r16, (1<<TWEN)
    sts  TWCR, r16

    ; Pengaturan Komunikasi Serial Debug (9600 BPS / bit per second)
    rcall uart_init
    ldi  ZL, lo8(str_dbg_boot)
    ldi  ZH, hi8(str_dbg_boot)
    rcall serial_print_str

    ; Inisialisasi awal variabel-variabel global program utama dalam register
    ldi  r20, 0             ; Status kondisi siklus mesin berjalan
    ldi  r21, 0             ; Kalkulator riwayat percobaan sandi salah (fail count)
    ldi  r22, 0             ; Panjang karakter input sandi berjalan
    ldi  r25, 0             ; Waktu tunda (counter delay) penguncian otomatis (auto-lock) saat mode terbuka

    rcall clear_input_buf   ; Bersihkan variabel sandi buffer di memory
    rcall clear_ovf_cnt     ; Bersihkan pencacah limit timer

    sei                     ; Izinkan interupsi global mulai bekerja (Global Interrupts)

    ; Urutan Antarmuka Boot Start-Up Modul Tampilan (LCD)
    rcall delay_50ms
    rcall lcd_init
    rcall lcd_show_startup  
    rcall delay_2s          
    rcall lcd_show_locked
    ldi  ZL, lo8(str_dbg_ready)
    ldi  ZH, hi8(str_dbg_ready)
    rcall serial_print_str

; FUNGSI: FUNGSI UTAMA (MAIN LOOP / FINITE STATE MACHINE)
; Pemetaan mode menggunakan register [r20]
; Keadaan terdefinisi:
;   STATE 0 = Locked / Mode Mengunci (Default)
;   STATE 1 = Unlocked / Mode Pintu Terbuka
;   STATE 2 = Temp Lock / Status Masa Tenggang (Kunci Sementara)
;   STATE 3 = Alarm / Sirine Terpanggil Karena Input Kasar
;   STATE 4 = Reset / Paksaan Pemulihan Mesin Normal (Emergency Reset)
main_loop:
    cpi  r20, 0
    breq do_locked
    cpi  r20, 1
    breq do_unlocked
    cpi  r20, 2
    breq do_templock
    cpi  r20, 3
    breq do_alarm
    cpi  r20, 4
    breq do_reset
    rjmp main_loop

do_locked:   rjmp state_locked
do_unlocked: rjmp state_unlocked
do_templock: rjmp state_templock
do_alarm:    rjmp state_alarm
do_reset:    rjmp state_reset


; STATE_RESET (Mode Reset Darurat)
; Menetralkan status mesin kembali ke STATE 0 normal dan menghapus buffer
state_reset:
    ldi  ZL, lo8(str_dbg_reset)
    ldi  ZH, hi8(str_dbg_reset)
    rcall serial_print_str
    rcall clear_input_buf
    rcall lcd_show_reset
    rcall delay_2s
    rcall lcd_show_locked
    ldi  r20, 0
    rjmp main_loop

; STATE_LOCKED (Mode Siklus Penguncian Normal Aktif)
; Sistem berada di posisi waspada (Standby) dan LED indikator Merah HIDUP (Sinyal Lock).
; Membaca hasil masukan matriks Keypad melalui fungsi keypad_scan (Reg. output > [r24]).
state_locked:
    sbi  PORTB, 2       ; Set PIN LED MERAH bernilai ON (Aktif)
    cbi  PORTB, 3       ; Set PIN LED HIJAU bernilai OFF (NonAktif)
    rcall buzzer_off
    rcall servo_lock    ; Beri pulsa Servo di fase posisi awal (0/Terkunci).

    ; Melakukan pemindaian matriks. Apabila tak menerima masukan, r24 otomatis menyimpan karakter kosong = 0xFF
    rcall keypad_scan
    cpi  r24, 0xFF
    breq locked_end
    rjmp sl_got_key

locked_end:
    rjmp main_loop

sl_got_key:
    ; Nilai dari register [r24] dipindahkan ke dalam proses memori tumpukan sementara
    ; Hal ini guna melindungi register diintervensi oleh operasi sistem suara piezo (buzzer_on) & fungsi waktu tunda (delay).
    push r24                
    rcall buzzer_on
    rcall delay_50ms
    rcall buzzer_off
    rcall wait_key_release  ; Transisi status ditahan hingga interaksi sentuhan (tombol lepas)
    pop  r24                

    ; [DEV] Menampilkan data antarmuka program Sistem Komunikasi Serial
    rcall serial_debug_key

    ; Bila karakter '*' dibaca, jalankan sub-prosedur memangkas karakter input.
    cpi  r24, '*'      
    breq sl_clear_input
    rjmp sl_save_key

sl_clear_input:
    ldi  ZL, lo8(str_dbg_clear)
    ldi  ZH, hi8(str_dbg_clear)
    rcall serial_print_str
    rcall clear_input_buf
    ldi  r22, 0
    rcall lcd_show_clearing
    rcall delay_50ms
    rcall delay_50ms
    rcall lcd_show_locked
    rjmp main_loop

; Rutin sl_save_key (Prosedur Memori Buffer)
; Memindahkan nilai karakter ascii Keypad [r24] ke dalam alamat memori (Pointer: INPUT_BUF).
; Register [r22] dipakai untuk mencacah perpindahan/pointer indeks buffer.
sl_save_key:
    ldi  XL, lo8(INPUT_BUF)
    ldi  XH, hi8(INPUT_BUF)
    add  XL, r22
    adc  XH, r1
    st   X, r24
    inc  r22

    ; [DEV] Menampilkan indikator angka memori (Length index progress)
    rcall serial_debug_count

    rcall lcd_show_input_progress

    cpi  r22, PWD_LEN
    breq sl_check_pwd
    rjmp main_loop

; Rutin sl_check_pwd (Pengecekan Komparasi Kunci)
; Menjalankan tes validasi komparasi kata sandi konstan program
; setelah jumlah blok memori panjang sandi mencapai syarat batas.
sl_check_pwd:
    ldi  ZL, lo8(str_dbg_check)
    ldi  ZH, hi8(str_dbg_check)
    rcall serial_print_str
    rcall verify_password   
    rcall clear_input_buf
    ldi  r22, 0

    cpi  r23, 1
    breq sl_password_ok

    ldi  ZL, lo8(str_dbg_wrong)
    ldi  ZH, hi8(str_dbg_wrong)
    rcall serial_print_str

    inc  r21
    rcall serial_debug_fail
    cpi  r21, 5
    breq sl_do_alarm
    cpi  r21, 3
    breq sl_do_templock

    rcall lcd_show_wrong
    rcall delay_2s
    rcall lcd_show_locked
    rjmp main_loop

sl_do_templock:
    ldi  ZL, lo8(str_dbg_templock)
    ldi  ZH, hi8(str_dbg_templock)
    rcall serial_print_str
    ldi  r20, 2
    rcall start_templock_timer
    rcall lcd_show_templock
    rjmp main_loop

sl_do_alarm:
    ldi  ZL, lo8(str_dbg_alarm)
    ldi  ZH, hi8(str_dbg_alarm)
    rcall serial_print_str
    ldi  r20, 3
    rcall lcd_show_alarm
    rjmp main_loop

sl_password_ok:
    ldi  ZL, lo8(str_dbg_ok)
    ldi  ZH, hi8(str_dbg_ok)
    rcall serial_print_str
    ldi  r21, 0             ; Reset kalkulator nilai sandi-salah (fail count)
    ldi  r20, 1             ; Daftarkan r20 dengan mode [1] / STATE_UNLOCKED
    rcall lcd_show_unlocked
    rjmp main_loop

; STATE_UNLOCKED (Mode Siklus Aktif: Kunci Bebas/Terbuka)
; Aktuasi Servo diputar (unlock). LED Merah OFF/MATI dan Hijau ON/HIDUP.
; Terdapat fitur proteksi mekanisme hitung lambat (counter delay loop) guna Auto-Lock
; Atau mode ini segera dikembalikan ke posisi Lock (Manual-Lock) jika menekan '#'.
state_unlocked:
    cbi  PORTB, 2       ; Set PIN LED MERAH bernilai OFF (NonAktif)
    sbi  PORTB, 3       ; Set PIN LED HIJAU bernilai ON (Aktif)
    rcall buzzer_off
    rcall servo_unlock
    
    rcall keypad_scan
    cpi  r24, '#'
    breq su_do_lock

    rcall delay_50ms
    inc  r25
    cpi  r25, 100       
    breq su_do_lock
    rjmp main_loop

su_do_lock:
    ldi  ZL, lo8(str_dbg_locking)
    ldi  ZH, hi8(str_dbg_locking)
    rcall serial_print_str
    ldi  r25, 0
    ldi  r20, 0
    rcall lcd_show_locking
    rcall delay_2s
    rcall lcd_show_locked
    rjmp main_loop

; STATE_TEMPLOCK (Mode Hukuman Ringan Sementara)
; Menahan modul sistem dari akses masuk jika user salah menginput pin 3x berturut-turut.
; Timer0 dikalkulasi menggunakan prinsip interrupt overflow (durasi est 5 detik).
state_templock:
    lds  r17, OVF_CNT_H
    lds  r16, OVF_CNT_L
    cpi  r16, TEMPLOCK_OVF_LO
    ldi  r18, TEMPLOCK_OVF_HI
    cpc  r17, r18
    brsh stl_timeout        ; Melompat jika target detik dicapai
    rjmp main_loop          ; Ulang siklus putar main_loop tanpa input masuk

stl_timeout:
    ldi  ZL, lo8(str_dbg_templock_done)
    ldi  ZH, hi8(str_dbg_templock_done)
    rcall serial_print_str
    rcall stop_templock_timer
    rcall clear_ovf_cnt
    ldi  r20, 0
    ldi  r22, 0
    rcall clear_input_buf
    rcall lcd_show_locked
    rjmp main_loop

; STATE_ALARM (Mode Hukuman Keras / Warning Keamanan)
; Puncaknya batas nilai pengulangan salah ke lima (5). Buzzer sirine ON dengan flasher LED MERAH. Program macet seutuhnya kecuali EXTINT RST menahan (Trigger Reset).
state_alarm:
    sbi  PORTB, 2       ; Set PIN LED MERAH bernilai ON (Aktif)
    cbi  PORTB, 3       ; Set PIN LED HIJAU bernilai OFF (NonAktif)
    rcall buzzer_on         
    rcall delay_50ms
    rcall delay_50ms
    cbi  PORTB, 2       
    rcall delay_50ms
    rcall delay_50ms
    rjmp main_loop          

; FUNGSI: FUNGSI VERIFIKASI KATA SANDI (VERIFY PASSWORD)
; Melakukan komparasi deret karakter memori SRAM di INPUT_BUF dengan sandi master
; Register [r23] akan bernilai 1 jika berhasil (True), atau 0 jika gagal (False).
verify_password:
    ldi  XL, lo8(INPUT_BUF)
    ldi  XH, hi8(INPUT_BUF)
    ld   r16, X+
    cpi  r16, PWD_0
    brne vp_fail
    ld   r16, X+
    cpi  r16, PWD_1
    brne vp_fail
    ld   r16, X+
    cpi  r16, PWD_2
    brne vp_fail
    ld   r16, X+
    cpi  r16, PWD_3
    brne vp_fail
    ldi  r23, 1
    ret
vp_fail:
    ldi  r23, 0
    ret

; FUNGSI: FUNGSI PEMINDAI MATRIKS KEYPAD (KEYPAD SCANNER ASCII)
; Membaca struktur keypad menggunakan pemindaian (multiplexing) baris x kolom.
; Sistem mendeteksi dengan memberikan logika LOW ke port Baris-ke(x) dan mem-validasi logika di Port PIND (Kolom).
; Dilengkapi fungsi waktu tunda rambatan (propagation delay) & kunci pelepasan.

; Rutin wait_key_release (Penahanan eksekusi menanti kontak fisik diputus)
wait_key_release:
    rcall delay_50ms        
    ; Mendorong nilai tarikan sinkron untuk seluruh baris PortC ke logika LOW 
    ldi  r18, 0x30
    out  PORTC, r18
    rcall delay_1ms         ; Memberi jendela waktu (delay) guna stabilisasi batas bouncing listrik
wkr_loop:
    in   r17, PIND
    andi r17, 0xF0          
    cpi  r17, 0xF0          ; Identifikasi apakah seluruh Input Pin di Port Kolom kembali HIGH (tombol terlepas)
    brne wkr_loop           ; Melambat dan terus re-loop sampai saklar putus sempurna
    
    rcall delay_50ms        
    ldi  r18, 0x3F          ; Restorasi register set PORTC memori
    out  PORTC, r18
    ret

; Rutin keypad_scan
; Register [r24] diisi karakter ASCII berdasarkan Keypad mapping (Misal = '1', 'A', '*')
; Jika matriks terputus / tak dihubungkan, dikembalikan 0xFF
keypad_scan:
    ldi  r24, 0xFF

    ; Pembacaan Interogasi Matriks Baris-1
    ldi  r18, 0x3E
    out  PORTC, r18
    rcall delay_1ms         ; Waktu tunda agar aliran listrik Wokwi stabil
    in   r17, PIND
    andi r17, 0xF0
    cpi  r17, 0xF0
    brne ks_row1

    ; Row 2
    ldi  r18, 0x3D
    out  PORTC, r18
    rcall delay_1ms
    in   r17, PIND
    andi r17, 0xF0
    cpi  r17, 0xF0
    brne ks_row2

    ; Row 3
    ldi  r18, 0x3B
    out  PORTC, r18
    rcall delay_1ms
    in   r17, PIND
    andi r17, 0xF0
    cpi  r17, 0xF0
    brne ks_row3

    ; Row 4
    ldi  r18, 0x37
    out  PORTC, r18
    rcall delay_1ms
    in   r17, PIND
    andi r17, 0xF0
    cpi  r17, 0xF0
    brne ks_row4

    rjmp ks_done            

ks_row1:
    cpi r17, 0xE0 
    breq k_1
    cpi r17, 0xD0 
    breq k_2
    cpi r17, 0xB0 
    breq k_3
    cpi r17, 0x70 
    breq k_A
    rjmp ks_done
    
ks_row2:
    cpi r17, 0xE0 
    breq k_4
    cpi r17, 0xD0 
    breq k_5
    cpi r17, 0xB0 
    breq k_6
    cpi r17, 0x70 
    breq k_B
    rjmp ks_done
    
ks_row3:
    cpi r17, 0xE0 
    breq k_7
    cpi r17, 0xD0 
    breq k_8
    cpi r17, 0xB0 
    breq k_9
    cpi r17, 0x70 
    breq k_C
    rjmp ks_done
    
ks_row4:
    cpi r17, 0xE0 
    breq k_star
    cpi r17, 0xD0 
    breq k_0
    cpi r17, 0xB0 
    breq k_hash
    cpi r17, 0x70 
    breq k_D
    rjmp ks_done

k_1: 
    ldi r24, '1' 
    rjmp ks_done
k_2: 
    ldi r24, '2' 
    rjmp ks_done
k_3: 
    ldi r24, '3' 
    rjmp ks_done
k_A: 
    ldi r24, 'A' 
    rjmp ks_done
k_4: 
    ldi r24, '4' 
    rjmp ks_done
k_5: 
    ldi r24, '5' 
    rjmp ks_done
k_6: 
    ldi r24, '6' 
    rjmp ks_done
k_B: 
    ldi r24, 'B' 
    rjmp ks_done
k_7: 
    ldi r24, '7' 
    rjmp ks_done
k_8: 
    ldi r24, '8' 
    rjmp ks_done
k_9: 
    ldi r24, '9' 
    rjmp ks_done
k_C: 
    ldi r24, 'C' 
    rjmp ks_done
k_star: 
    ldi r24, '*' 
    rjmp ks_done
k_0: 
    ldi r24, '0' 
    rjmp ks_done
k_hash: 
    ldi r24, '#' 
    rjmp ks_done
k_D: 
    ldi r24, 'D' 
    rjmp ks_done

ks_done:
    ldi  r18, 0x3F          
    out  PORTC, r18
    ret

; FUNGSI: FUNGSI INTERUPSI / INTERRUPT SERVICE ROUTINES (ISR)

; ISR TIMER0_OVF_vect (Vektor Interupsi Eksekusi Timer0 Overflow)
; Terpanggil otomatis saat register kalkulasi Timer0 mentok ke nilai maks lalu overflow.
; Modus perlindungan register (SREG dipindah ke Stack) digunakan mencegah status flag global berubah.
; Otomatis menambah nilai pada alamat SRAM OVF_CNT_L/OVF_CNT_H mengalkulasi masa penangguhan waktu timeout.
.global TIMER0_OVF_vect
TIMER0_OVF_vect:
    push r16
    in   r16, SREG
    push r16
    lds  r16, OVF_CNT_L
    inc  r16
    sts  OVF_CNT_L, r16
    brne t0ovf_exit         
    lds  r16, OVF_CNT_H
    inc  r16
    sts  OVF_CNT_H, r16
t0ovf_exit:
    pop  r16
    out  SREG, r16
    pop  r16
    reti

; ISR INT0_vect (Vektor Interupsi Eksternal Port INT0)
; Akan berjalan tiba-tiba di sisi perhitungan utama manakala pin INT0 mendeteksi masukan FALLING EDGE.
; Memaksa variabel STATE melompat memutus kalkulasi sirine (Reset Emergency), dan memutus sinyal Timer2/PWM Buzzer. 
; Info: Memanggil fungsi print I2C / String UART di dalam ISR dapat mengganggu program, maka hanya register STATE penyimpan flag reset saja yang dimodifikasi.
.global INT0_vect
INT0_vect:
    push r16
    in   r16, SREG
    push r16

    ; Eksekusi penghentian darurat (matikan PWM buzzer dari Timer2)
    sts  TCCR2A, r1
    sts  TCCR2B, r1
    cbi  PORTD, 3

    out  TCCR0B, r1
    sts  OVF_CNT_H, r1
    sts  OVF_CNT_L, r1

    ldi  r20, 4   
    ldi  r21, 0   
    ldi  r22, 0   

    pop  r16
    out  SREG, r16
    pop  r16
    reti

; FUNGSI: FUNGSI AKTUALISASI SISTEM / PENDUKUNG VARIABEL UTAMA & FUNGSI WAKTU JEDA

; clear_input_buf (Penghapus Alokasi Buffer Memori RAM)
; Menetralkan pointer alamat X mulai dari blok SRAM INPUT_BUF sebanyak PWD_LEN (4 byte).
clear_input_buf:
    ldi  XL, lo8(INPUT_BUF)
    ldi  XH, hi8(INPUT_BUF)
    ldi  r16, 0xFF
    ldi  r17, PWD_LEN
cib_loop:
    st   X+, r16
    dec  r17
    brne cib_loop
    ret

clear_ovf_cnt:
    sts  OVF_CNT_H, r1
    sts  OVF_CNT_L, r1
    ret

start_templock_timer:
    rcall clear_ovf_cnt
    out  TCNT0, r1                                 
    ldi  r16, (1<<CS02) | (1<<CS00)        
    out  TCCR0B, r16
    ret

stop_templock_timer:
    out  TCCR0B, r1         
    ret

; buzzer_on
; Menginisiasi kanal sinyal (Duty Cycle) pembentuk nada melalui output ke PIN Buzzer [PD3/OC2B] dengan menggunakan modulasi Fast PWM Timer2.
buzzer_on:
    ldi  r16, (1<<WGM21) | (1<<WGM20) | (1<<COM2B1)
    sts  TCCR2A, r16
    ldi  r16, (1<<CS22) | (1<<CS21) | (1<<CS20)
    sts  TCCR2B, r16
    ldi  r16, 128
    sts  OCR2B, r16
    ret

; buzzer_off
; Memutus aliran sinyal Fast PWM prescaler sistem kontrol.
buzzer_off:
    sts  TCCR2A, r1
    sts  TCCR2B, r1
    cbi  PORTD, 3
    ret

; servo_lock
; Mengirim batas tugas sinyal PWM Servo singkat agar aktuator tertarik mundur (Mengikat Slot Jendela).
servo_lock:
    ldi  r16, hi8(2000)
    sts  OCR1AH, r16
    ldi  r16, lo8(2000)
    sts  OCR1AL, r16
    ret

; servo_unlock
; Batas amplitudo diperlebar, aktuator ditarik membuka Slot penahan.
servo_unlock:
    ldi  r16, hi8(4000)
    sts  OCR1AH, r16
    ldi  r16, lo8(4000)
    sts  OCR1AL, r16
    ret

delay_1ms:
    push r18
    push r19
    ldi  r19, 21
d1ms_o: ldi  r18, 0xFF
d1ms_i: dec  r18
    brne d1ms_i
    dec  r19
    brne d1ms_o
    pop  r19
    pop  r18
    ret

delay_50ms:
    push r19
    ldi  r19, 50
d50ms_l: rcall delay_1ms
    dec  r19
    brne d50ms_l
    pop  r19
    ret

delay_2s:
    push r19
    ldi  r19, 40
d2s_l:  rcall delay_50ms
    dec  r19
    brne d2s_l
    pop  r19
    ret

; FUNGSI: PROTOKOL PENGIRIMAN DATA UART (SERIAL) - 9600 BPS @ F_CPU: 16 MHz

; Rutin Pendefinisian Mode Debug uart_init
; Nilai kalkulasi UBRR0 dihitung ke [103] digunakan bila baud rate bernilai konstan 9600 (Untuk limit osilator hardware MCU dasar bernilai 16MHz).
uart_init:
    ldi  r16, hi8(103)
    sts  UBRR0H, r16
    ldi  r16, lo8(103)
    sts  UBRR0L, r16
    ldi  r16, (1<<TXEN0)
    sts  UCSR0B, r16
    ldi  r16, (1<<UCSZ01) | (1<<UCSZ00)
    sts  UCSR0C, r16
    ret

; Rutin serial_write_r24 
; Kirim karakter buffer (berdasar isi register r24). Register r16 jadi register perlindungan tumpukan stack.
serial_write_r24:
    push r16
swr_wait:
    lds  r16, UCSR0A
    sbrs r16, UDRE0
    rjmp swr_wait
    sts  UDR0, r24
    pop  r16
    ret

; Rutin serial_print_str 
; Melangkahkan pointer program memori ROM/Flash via register [Z] ke Alamat pointer blok data konstan (.string).
serial_print_str:
    push r16
    push r25
sps_loop:
    lpm  r25, Z+
    cpi  r25, 0
    breq sps_done
    mov  r24, r25
    rcall serial_write_r24
    rjmp sps_loop
sps_done:
    pop  r25
    pop  r16
    ret

serial_newline:
    ldi  r24, 13
    rcall serial_write_r24
    ldi  r24, 10
    rcall serial_write_r24
    ret

; Rutin serial_debug_key 
; Mentransfer masukan karakter saklar ke terminal UART dengan menahan data register pembaca ke tumpukan sementara (push r24)
serial_debug_key:
    push r24
    ldi  ZL, lo8(str_dbg_key)
    ldi  ZH, hi8(str_dbg_key)
    rcall serial_print_str
    pop  r24
    push r24
    rcall serial_write_r24
    rcall serial_newline
    pop  r24
    ret

; Rutin serial_debug_count 
; Menampilkan hasil perhitungan indikator/progress panjang batas indeks yang dicapai (nilai r22). 
; Dikonversi ke cetak/karakter huruf dengan format offset batas awal ASCII -'0'.
serial_debug_count:
    push r24
    ldi  ZL, lo8(str_dbg_count)
    ldi  ZH, hi8(str_dbg_count)
    rcall serial_print_str
    mov  r24, r22
    subi r24, -'0'
    rcall serial_write_r24
    rcall serial_newline
    pop  r24
    ret

; Rutin serial_debug_fail 
; Memanggil informasi kegagalan batas kata sandi salah ([r21]), ditambahkan ke -'0' untuk nilai literal cetak Terminal.
serial_debug_fail:
    push r24
    ldi  ZL, lo8(str_dbg_fail)
    ldi  ZH, hi8(str_dbg_fail)
    rcall serial_print_str
    mov  r24, r21
    subi r24, -'0'
    rcall serial_write_r24
    rcall serial_newline
    pop  r24
    ret

; FUNGSI: FUNGSI PUSTAKA ANTARMUKA TWI / I2C OLEH MODUL LCD

; Rutin Pendefinisian Kondisi Awal Transmisi Data I2C (twi_start)
; Memulai transmisi sinyal sinkronisasi instruksi START.
twi_start:
    ldi  r16, (1<<TWINT) | (1<<TWSTA) | (1<<TWEN)
    sts  TWCR, r16
twi_start_w:
    lds  r16, TWCR
    sbrs r16, TWINT
    rjmp twi_start_w
    ret

twi_stop:
    ldi  r16, (1<<TWINT) | (1<<TWSTO) | (1<<TWEN)
    sts  TWCR, r16
    ret

twi_write_byte:
    sts  TWDR, r25
    ldi  r16, (1<<TWINT) | (1<<TWEN)
    sts  TWCR, r16
twi_wb_w:
    lds  r16, TWCR
    sbrs r16, TWINT
    rjmp twi_wb_w
    ret

i2c_lcd_write_nibble:
    rcall twi_start
    ldi  r25, LCD_ADDR_W
    rcall twi_write_byte
    mov  r25, r18
    ori  r25, LCD_EN     
    rcall twi_write_byte
    rcall twi_stop
    rcall delay_1ms      

    rcall twi_start
    ldi  r25, LCD_ADDR_W
    rcall twi_write_byte
    mov  r25, r18        
    rcall twi_write_byte
    rcall twi_stop
    rcall delay_1ms      
    ret

; Rutin Pengiriman Komunikasi Data Display LCD (lcd_send)
; Mentransfer satu unit frame (8 bit / 1 byte) blok ke LCD melalui konversi ke perlakuan logik mesin mode operasi 4-bit (Half-Byte / Nibble).
; Proses dieksekusi dengan mendahulukan pemotongan 4-bit paruh yang tinggi lalu dikirim bergantian bersama nibble 4-bit paruh yang rendah.
lcd_send:
    push r25                
    push r16                
    ldi  r17, LCD_BACKLIGHT
    or   r17, r16           
    mov  r18, r25
    andi r18, 0xF0          
    or   r18, r17           
    rcall i2c_lcd_write_nibble
    pop  r16                
    pop  r25                
    ldi  r17, LCD_BACKLIGHT
    or   r17, r16
    swap r25
    andi r25, 0xF0
    or   r25, r17
    mov  r18, r25           
    rcall i2c_lcd_write_nibble
    ret

lcd_cmd:
    ldi  r16, 0
    rcall lcd_send
    ret

lcd_data:
    ldi  r16, LCD_RS
    rcall lcd_send
    ret

lcd_clear:
    ldi  r25, 0x01
    rcall lcd_cmd
    rcall delay_50ms        
    ret

lcd_set_cursor:
    ldi  r25, 0x80          
    cpi  r18, 0
    breq lsc_apply
    ldi  r25, 0xC0          
lsc_apply:
    add  r25, r19
    rcall lcd_cmd
    ret

lcd_print_str:
    lpm  r25, Z+
    cpi  r25, 0
    breq lps_end
    rcall lcd_data
    rjmp lcd_print_str
lps_end:
    ret

lcd_init:
    rcall delay_50ms        
    ldi  r18, 0x30 | LCD_BACKLIGHT
    rcall i2c_lcd_write_nibble
    rcall delay_50ms        
    ldi  r18, 0x30 | LCD_BACKLIGHT
    rcall i2c_lcd_write_nibble
    rcall delay_50ms        
    ldi  r18, 0x30 | LCD_BACKLIGHT
    rcall i2c_lcd_write_nibble
    rcall delay_50ms
    ldi  r18, 0x20 | LCD_BACKLIGHT
    rcall i2c_lcd_write_nibble
    rcall delay_50ms
    ldi  r25, 0x28          
    rcall lcd_cmd
    ldi  r25, 0x0C          
    rcall lcd_cmd
    ldi  r25, 0x01          
    rcall lcd_cmd
    rcall delay_50ms
    ldi  r25, 0x06          
    rcall lcd_cmd
    ret

; DEKLARASI BLOK MEMORI: TEKS STRING DAN USER INTERFACE (UI) LAYAR
str_dbg_boot:          .string "[BOOT] Serial OK, system init...\r\n"
str_dbg_ready:         .string "[READY] State LOCKED, waiting keypad.\r\n"
str_dbg_key:           .string "[KEY] Pressed: "
str_dbg_count:         .string "[INPUT] Count: "
str_dbg_check:         .string "[CHECK] 4 digits entered, verifying password.\r\n"
str_dbg_ok:            .string "[PASS] Correct password, door open.\r\n"
str_dbg_wrong:         .string "[PASS] Wrong password.\r\n"
str_dbg_fail:          .string "[FAIL] Fail count: "
str_dbg_clear:         .string "[CLEAR] Input cleared by '*'.\r\n"
str_dbg_templock:      .string "[STATE] TEMP LOCK activated after 3 fails.\r\n"
str_dbg_templock_done: .string "[STATE] TEMP LOCK finished, back to LOCKED.\r\n"
str_dbg_alarm:         .string "[STATE] ALARM activated after 5 fails. Press emergency reset.\r\n"
str_dbg_reset:         .string "[RESET] Emergency reset triggered.\r\n"
str_dbg_locking:       .string "[LOCK] Door locked.\r\n"

str_startup_r0:  .string "Protected Door  "
str_startup_r1:  .string "                "

str_locked_r0:   .string "Enter Password: "
str_locked_r1:   .string "                "

str_input_r0:    .string "Enter Password: "
str_input_pfx:   .string ""

str_unlocked_r0: .string "  Door is Open  "
str_unlocked_r1: .string "                "

str_locking_r0:  .string "Door is closed  "
str_locking_r1:  .string "                "

str_wrong_r0:    .string "Wrong Password  "
str_wrong_r1:    .string "                "

str_templock_r0: .string "TEMP LOCKED!    "
str_templock_r1: .string "Wait 5 secs...  "

str_alarm_r0:    .string "!!! ALARM !!!   "
str_alarm_r1:    .string "                "

str_reset_r0:    .string "System Reset!   "
str_reset_r1:    .string "                "

str_clearing_r0: .string "Clearing...     "
str_clearing_r1: .string "                "

lcd_show_startup:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_startup_r0)
    ldi  ZH, hi8(str_startup_r0)
    rcall lcd_print_str
    ret

lcd_show_locked:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_locked_r0)
    ldi  ZH, hi8(str_locked_r0)
    rcall lcd_print_str
    ret

; Rutin lcd_show_input_progress
; Menampilkan riwayat rentetan pemencetan digit sandi masukan pada baris kedua matriks tampilan.
; [PERBAIKAN BUG]: Eksekusi mencetak array akan merombak register [r17], padahal [r17] mendasari indeks kalkulasi pencacah lcd_send. Tumpukan operasi keselamatan harus tersusun dan melingkupi prosedur rcall lcd_data via mekanisme stack tumpukan data (push r17 & pop r17) guna menjamin UI tergambar sempurna.
lcd_show_input_progress:
    push r22
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_input_r0)
    ldi  ZH, hi8(str_input_r0)
    rcall lcd_print_str

    ldi  r18, 1
    ldi  r19, 0
    rcall lcd_set_cursor

    pop  r22
    push r22
    mov  r17, r22
    tst  r17
    breq lip_blanks

    ; Proses Iterasi Pencetakan Representasi Teks Berdasar Alamat SRAM Pointer X
    ldi  XL, lo8(INPUT_BUF)
    ldi  XH, hi8(INPUT_BUF)
lip_chars:
    ld   r25, X+
    ldi  r25, '*'           ; 
    push r17                ; Mengisolasi batas Register [r17] dengan memidahkan ke ruang memori tumpukan sementara
    rcall lcd_data
    pop  r17
    dec  r17
    brne lip_chars

lip_blanks:
    ldi  r17, PWD_LEN
    pop  r22
    push r22
    sub  r17, r22
    tst  r17
    breq lip_done

lip_unders:
    ldi  r25, '-'           ; Menyetel Karakter Placeholder (Diganti format strip-tengah supaya tak dikelirukan karakter black box bawaan layar)
    push r17                ; Mengisolasi batas Register [r17] dengan memidahkan ke ruang memori tumpukan sementara
    rcall lcd_data
    pop  r17
    dec  r17
    brne lip_unders

lip_done:
    pop  r22
    ret

lcd_show_unlocked:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_unlocked_r0)
    ldi  ZH, hi8(str_unlocked_r0)
    rcall lcd_print_str
    ret

lcd_show_locking:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_locking_r0)
    ldi  ZH, hi8(str_locking_r0)
    rcall lcd_print_str
    ret

lcd_show_wrong:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_wrong_r0)
    ldi  ZH, hi8(str_wrong_r0)
    rcall lcd_print_str
    ret

lcd_show_templock:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_templock_r0)
    ldi  ZH, hi8(str_templock_r0)
    rcall lcd_print_str
    ldi  r18, 1
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_templock_r1)
    ldi  ZH, hi8(str_templock_r1)
    rcall lcd_print_str
    ret

lcd_show_alarm:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_alarm_r0)
    ldi  ZH, hi8(str_alarm_r0)
    rcall lcd_print_str
    ret

lcd_show_reset:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_reset_r0)
    ldi  ZH, hi8(str_reset_r0)
    rcall lcd_print_str
    ret

lcd_show_clearing:
    rcall lcd_clear
    ldi  r18, 0
    ldi  r19, 0
    rcall lcd_set_cursor
    ldi  ZL, lo8(str_clearing_r0)
    ldi  ZH, hi8(str_clearing_r0)
    rcall lcd_print_str
    ret