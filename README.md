# 🤖 Install AI PyTorch (VPS Setup Guide)

Selamat datang! Repo ini berisi *script ajaib* `setup.sh` yang akan menyulap VPS kosong (Ubuntu/Debian) kamu menjadi server AI pribadi yang tangguh.

Hanya dengan satu perintah, script ini akan menginstall dan mengonfigurasi **Ollama** (untuk menjalankan model bahasa lokal) dan **OpenClaw** (asisten AI visual berbasis web) secara otomatis.

---

## 🌟 Apa yang akan kamu dapatkan?

1. **Ollama** terinstall dan berjalan sebagai _background service_ (bisa diakses dari Docker).
2. **Dua Model AI Gratis & Open Source**:
   - 👁️ `qwen2.5vl:72b` (Lebih dari 40GB) - Model khusus untuk membaca dan mengerti gambar (Vision).
   - 🧠 `qwen3.5:122b` (Lebih dari 80GB) - Model super cerdas untuk ngobrol, coding, dan tugas agen AI.
3. **OpenClaw Dashboard** siap pakai, terhubung ke Ollama kamu + bonus sistem keamanan Token agar servermu aman.

---

## 📋 Persyaratan Sistem

Sebelum mulai, pastikan VPS kamu memenuhi syarat berikut:
- **OS:** Ubuntu 20.04+ atau Debian 11+
- **GPU:** AMD seri MI (dengan ROCm) **ATAU** NVIDIA (dengan CUDA)
- **VRAM / RAM:** Minimal 48GB VRAM (kalau cuma mau model Vision), atau **di atas 128GB** kalau mau jalanin kedua model sekaligus!
- **Internet:** Koneksi stabil untuk download model berukuran besar.

*(Script ini sudah sukses dites di GPU AMD MI300X dengan 192GB VRAM)*

---

## 🚀 Langkah 1: Download & Install

Buka terminal VPS kamu (via SSH), lalu jalankan perintah ini berturut-turut:

```bash
# 1. Download script ke VPS kamu
git clone https://github.com/Arjawa10/install-ai-pytorch.git

# 2. Masuk ke foldernya
cd install-ai-pytorch

# 3. Jalankan script utamanya!
bash setup.sh
```

Nanti di layar akan muncul beberapa pilihan. Kalau kamu baru pertama kali, **pilih Mode 3 (Full Setup)**. Script ini pintar, dia akan otomatis mendeteksi apakah kamu pakai AMD atau NVIDIA.

> **Tips:** Mau nge-teh dulu? Silakan! Proses download modelnya cukup lama tergantung kecepatan internet VPS kamu (total file bisa di atas 120GB!).

---

## 🌐 Langkah 2: Cara Buka Dashboard OpenClaw

Setelah instalasi selesai, script akan memberikan kamu sebuah **Gateway Token**. Simpan token ini baik-baik!

Untuk alasan keamanan, sistem modern browser (seperti Chrome/Edge) mewajibkan koneksi ke OpenClaw menggunakan jaringan yang aman (HTTPS) atau jaringan lokal (localhost). Karena VPS kamu cuma punya IP Publik, kita akan pakai trik gampang bernama **SSH Tunnel**.

Buka terminal/PowerShell di **Laptop/PC Windows kamu** (bukan di VPS ya), dan jalankan perintah ini:

**Bila kamu menggunakan File Key `.ppk` (PuTTY):**
```powershell
plink -N -L 18789:127.0.0.1:18789 -i "C:\Lokasi\Key\Kamu.ppk" root@IP_VPS_KAMU
```

**Bila kamu menggunakan File Key biasa (OpenSSH):**
```powershell
ssh -N -L 18789:127.0.0.1:18789 -i "C:\Lokasi\Key\Kamu.pem" root@IP_VPS_KAMU
```
*(Catatan: Layar terminal akan terlihat seperti "nge-hang" dan tidak keluar tulisan apa-apa. Ini normal! Biarkan jendelanya tetap terbuka).*

Sekarang, buka browser favoritmu dan ketik:
👉 **`http://localhost:18789/`**

Tada! Dashboard OpenClaw akan terbuka. Tuliskan/paste **Gateway Token** yang kamu dapatkan di akhir langkah instalasi. Assistant kamu sudah siap diajak ngobrol!

---

## 🛠️ Kemampuan Ekstra (Untuk Developer)

### 1. Ekstrak Metadata Gambar Otomatis (Vision AI)
Script ini menyediakan file `vlm_metadata_export.py`. Fungsinya untuk membaca folder berisi ratusan gambar, dan AI akan membuatkan file Excel/CSV berisi deskripsi, judul, kategori, dan mood dari setiap gambar tersebut secara otomatis!

**Cara Pakainya:**
```bash
python3 vlm_metadata_export.py \
    --folder /folder/lokasi/gambar/kamu \
    --output hasil_metadata.csv \
    --model qwen2.5vl:72b \
    --ollama-url http://localhost:11434
```

### 2. Panggil API Lewat Jaringan Docker
Kalau kamu bikin aplikasi pakai Docker di dalam VPS ini (seperti JupyterLab, Laravel, dsb), kamu bisa panggil Ollama tanpa ribet masukin IP Publik. Cukup arahkan koneksi ke Gateway Docker:

```bash
# Contoh tes koneksi via CURL dari dalam container Docker
curl http://172.17.0.1:11434/api/tags
```

---

## 🚑 Pertolongan Pertama (Troubleshooting)

Ada yang error? Tenang, cek solusinya di sini:

### Masalah 1: "pairing required" atau "control ui requires device identity"
Itu tandanya kamu akses dashboard langsung dari HTTP IP Publik (misal: `http://123.45.67.89:18789`). Browser menolaknya.
**Solusi:** Kembalilah ke **Langkah 2** di atas dan gunakan SSH Tunnel (`http://localhost:18789`).

### Masalah 2: Gateway Not Accessible / Koneksi Refused
Jika SSH Tunnel tidak bisa nyambung, bisa jadi Firewall VPS kamu belum buka port aslinya atau gateway belum running. Jawabannya, jalankan di VPS kamu:
```bash
# Izinkan Port 18789 di Firewall (Penting buat OpenClaw)
sudo ufw allow 18789/tcp
sudo iptables -I INPUT -p tcp --dport 18789 -j ACCEPT

# Pastikan gateway hidup
openclaw gateway start --port 18789
```

### Masalah 3: GPU Tidak Terdeteksi? (Response AI lambat)
Coba jalankan cek GPU ini di VPS:
- Punya **NVIDIA**? ketik: `nvidia-smi`
- Punya **AMD**? ketik: `rocminfo | grep -i gpu`

Kalau error/kosong, berarti driver GPU VPS kamu bermasalah atau belum terinstall dengan benar dari pihak provider server.

### Masalah 4: Lupa Gateway Token OpenClaw
Gampang, cek lagi token kamu kapan saja dengan menjalankan ini di VPS:
```bash
openclaw config get gateway.auth.token
```

---
*Happy Coding & Exploring AI! 🚀*
