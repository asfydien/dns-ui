# DNS UI - Simple DNS Zone Editor for dnsmasq

Antarmuka web minimalis berbasis PHP untuk mengelola DNS Record lokal (`A`, `CNAME`, `MX`) pada server `dnsmasq`. Aplikasi ini dirancang khusus untuk kebutuhan laboratorium komputer, simulasi administrasi server, serta pengujian *Virtual Host* di lingkungan *Host-Only* atau *air-gapped* tanpa memerlukan koneksi internet aktif.

---

## Fitur Utama

- **Zero-Dependency Web Server**: Berjalan langsung menggunakan PHP CLI Built-in Web Server tanpa perlu memasang Apache atau Nginx tambahan.
- **Port Khusus (1919)**: Tidak mengganggu alokasi port web standar (80, 443) maupun port kontrol panel hosting (seperti CloudPanel di port 8443).
- **Auto-Reload Service**: Konfigurasi otomatis disimpan ke `/etc/dnsmasq.d/custom_records.conf` dan layanan `dnsmasq` langsung dimuat ulang seketika.
- **Live Preview Konfigurasi**: Menampilkan sintaks berkas konfigurasi asli secara langsung sehingga siswa dapat mempelajari korelasi antara UI dan konfigurasi teks Linux.
- **Hemat Resource**: Konsumsi RAM sangat rendah, ideal dijalankan pada mesin virtual (VM) dengan alokasi memori terbatas.

---

## Skema Kerja Jaringan Lab

Aplikasi ini dirancang untuk skenario 1 VM Server (Debian) dengan PC Host fisik sebagai klien penguji:

```text
[ PC Host Fisik ] (Browser & CMD)
       |
       |  (Jaringan Host-Only / VMnet1)
       v
[ VM Debian 13 ] 
       ├── DNS Server (dnsmasq)      : Port 53
       ├── DNS Web UI (PHP Built-in) : Port 1919
       └── Web Server / Control Panel: Port 80 / 8443
```

---

## Persyaratan Sistem

- **Sistem Operasi**: Debian 12 / 13 atau Ubuntu 22.04 / 24.04 LTS
- **Hak Akses**: Root / Sudo
- **Paket yang Dibutuhkan**: `dnsmasq`, `php-cli`, `curl`

---

## Panduan Instalasi

### 1. Instalasi Otomatis (Satu Baris Perintah)

Jalankan perintah berikut langsung di terminal VM Debian:

```bash
curl -sSL https://raw.githubusercontent.com/asfydien/dns-ui/main/install-dns-ui.sh | sudo bash
```

### 2. Instalasi Manual via Git

Jika ingin meninjau skrip sebelum mengeksekusi:

```bash
git clone https://github.com/asfydien/dns-ui.git
cd dns-ui
chmod +x install-dns-ui.sh
sudo ./install-dns-ui.sh
```

Setelah instalasi selesai, layanan `dns-ui.service` akan otomatis aktif di latar belakang.

---

## Cara Penggunaan

1. Pastikan kartu jaringan VM menggunakan adapter **Host-Only**.
2. Buka peramban di PC Host (laptop fisik), lalu akses alamat:
   ```text
   http://<IP_VM_DEBIAN>:1919
   ```
   *(Contoh: `http://192.168.100.10:1919`)*
3. Pilih tipe record (`A`, `CNAME`, atau `MX`), masukkan nama domain lokal (misal: `portal.belajar.test`), masukkan target IP/host, lalu klik **+ Simpan**.

---

## Pengujian dari PC Host

Lakukan verifikasi hasil konfigurasi dari Command Prompt (Windows) atau Terminal (Linux/macOS) pada laptop host:

**Uji A Record**
```cmd
nslookup portal.belajar.test <IP_VM_DEBIAN>
```

**Uji CNAME Record**
```cmd
nslookup -type=cname www.belajar.test <IP_VM_DEBIAN>
```

**Uji MX Record**
```cmd
nslookup -type=mx sekolah.test <IP_VM_DEBIAN>
```

---

## Struktur Berkas Sistem

| Lokasi | Fungsi |
| :--- | :--- |
| `/opt/dns-ui/index.php` | Berkas inti antarmuka web dan pemroses konfigurasi |
| `/etc/dnsmasq.d/custom_records.conf` | Berkas penyimpanan entri DNS record hasil input UI |
| `/etc/systemd/system/dns-ui.service` | Berkas unit service systemd untuk menjalankan web server |

---

## Manajemen Layanan

Layanan web UI dikelola melalui `systemd`:

- Memeriksa status:
  ```bash
  sudo systemctl status dns-ui
  ```
- Memuat ulang layanan:
  ```bash
  sudo systemctl restart dns-ui
  ```
- Menghentikan layanan:
  ```bash
  sudo systemctl stop dns-ui
  ```

---
## Catatan Integrasi: CloudPanel & Firewall (UFW)

Jika menjalankan `dns-ui` bersamaan dengan kontrol panel hosting seperti **CloudPanel**, skrip instalasi panel tersebut secara otomatis akan mengaktifkan firewall `ufw` dan mengunci seluruh port yang tidak digunakan oleh layanannya. 

Kondisi ini menyebabkan port web **1919** (`dns-ui`) dan port **53** (`dnsmasq`) terblokir dari akses jaringan luar (host).

Untuk mengizinkan lalu lintas data kembali, jalankan perintah berikut di terminal VM:

```bash
# Buka port web DNS UI
sudo ufw allow 1919/tcp comment "DNS UI Web"

# Buka port DNS dnsmasq (TCP & UDP)
sudo ufw allow 53 comment "dnsmasq DNS Server"

# Terapkan perubahan firewall
sudo ufw reload
```

---
## Lisensi

Proyek ini didistribusikan di bawah lisensi **MIT**. Silakan gunakan, modifikasi, dan bagikan kembali untuk keperluan pendidikan maupun praktikum.
