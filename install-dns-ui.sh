#!/bin/bash
# ==========================================================
# Installer Otomatis DNS Zone Editor (dnsmasq)
# Repositori: asfydien/dns-ui
# Port Default: 1919
# Fitur: Record A/AAAA/CNAME/MX/TXT, Tab Navigasi, 
#        Pengaturan /etc/resolv.conf
# ==========================================================

set -e

# 1. Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "[!] Jalankan skrip ini dengan hak akses root (sudo)."
  exit 1
fi

echo "[*] Memperbarui indeks paket dan memasang dependensi (dnsmasq & php-cli)..."
apt-get update -y > /dev/null
apt-get install -y dnsmasq php-cli > /dev/null

# 2. Siapkan direktori dan berkas konfigurasi dnsmasq
echo "[*] Menyiapkan konfigurasi dnsmasq..."
mkdir -p /etc/dnsmasq.d
touch /etc/dnsmasq.d/custom_records.conf

# Pastikan dnsmasq membaca folder conf-dir
if ! grep -q "^conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf 2>/dev/null; then
    echo "conf-dir=/etc/dnsmasq.d/,*.conf" >> /etc/dnsmasq.conf
fi

# 3. Siapkan direktori aplikasi
APP_DIR="/opt/dns-ui"
echo "[*] Menyiapkan direktori aplikasi di ${APP_DIR}..."
mkdir -p "${APP_DIR}"

# 4. Tulis aplikasi PHP terintegrasi (Backend + Frontend Tabbed Interface)
cat << 'EOF' > "${APP_DIR}/index.php"
<?php
session_start();

$configFile = '/etc/dnsmasq.d/custom_records.conf';
$resolvFile = '/etc/resolv.conf';

// Deteksi alamat IP server aktif
$serverIp = trim(shell_exec("hostname -I | awk '{print $1}'")) ?: ($_SERVER['SERVER_ADDR'] ?? '127.0.0.1');

// Parsing berkas dnsmasq
function parseDnsRecords($filePath) {
    $records = [];
    if (!file_exists($filePath)) return $records;
    
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $index => $line) {
        $line = trim($line);
        if (str_starts_with($line, '#')) continue;

        if (preg_match('/^address=\/(.+?)\/(.+)$/', $line, $m)) {
            $isIpv6 = str_contains($m[2], ':');
            $records[] = [
                'id' => $index, 
                'type' => $isIpv6 ? 'AAAA' : 'A', 
                'domain' => $m[1], 
                'target' => $m[2], 
                'priority' => '-'
            ];
        } elseif (preg_match('/^cname=(.+?),(.*)$/', $line, $m)) {
            $records[] = [
                'id' => $index, 
                'type' => 'CNAME', 
                'domain' => $m[1], 
                'target' => $m[2], 
                'priority' => '-'
            ];
        } elseif (preg_match('/^mx-host=(.+?),(.*?)(?:,(\d+))?$/', $line, $m)) {
            $records[] = [
                'id' => $index, 
                'type' => 'MX', 
                'domain' => $m[1], 
                'target' => $m[2], 
                'priority' => $m[3] ?? '10'
            ];
        } elseif (preg_match('/^txt-record=(.+?),(.*)$/', $line, $m)) {
            $cleanTarget = trim($m[2], '"');
            $records[] = [
                'id' => $index, 
                'type' => 'TXT', 
                'domain' => $m[1], 
                'target' => $cleanTarget, 
                'priority' => '-'
            ];
        }
    }
    return $records;
}

// Proses form POST
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    if ($action === 'add') {
        $type = $_POST['type'] ?? 'A';
        $domain = trim($_POST['domain'] ?? '');
        $target = trim($_POST['target'] ?? '');
        $prio = (int)($_POST['priority'] ?? 10);

        if ($domain !== '' && $target !== '') {
            $entry = '';
            if ($type === 'A' || $type === 'AAAA') {
                $entry = "address=/{$domain}/{$target}\n";
            } elseif ($type === 'CNAME') {
                $entry = "cname={$domain},{$target}\n";
            } elseif ($type === 'MX') {
                $entry = "mx-host={$domain},{$target},{$prio}\n";
            } elseif ($type === 'TXT') {
                $escapedTarget = trim($target, '"');
                $entry = "txt-record={$domain},\"{$escapedTarget}\"\n";
            }

            $currentData = file_exists($configFile) ? file_get_contents($configFile) : '';
            if (str_contains($currentData, trim($entry))) {
                $_SESSION['error'] = "Record {$type} [{$domain}] sudah terdaftar!";
            } else {
                file_put_contents($configFile, $entry, FILE_APPEND | LOCK_EX);
                shell_exec('systemctl restart dnsmasq');
                $_SESSION['message'] = "Record {$type} [{$domain}] berhasil ditambahkan!";
            }
        } else {
            $_SESSION['error'] = "Domain dan Target/Nilai wajib diisi.";
        }
        header("Location: index.php?tab=records");
        exit;
    } elseif ($action === 'delete') {
        $idToDelete = (int)$_POST['id'];
        $lines = file($configFile, FILE_IGNORE_NEW_LINES);
        if (isset($lines[$idToDelete])) {
            unset($lines[$idToDelete]);
            file_put_contents($configFile, implode("\n", $lines) . (count($lines) > 0 ? "\n" : ""), LOCK_EX);
            shell_exec('systemctl restart dnsmasq');
            $_SESSION['message'] = "Record DNS berhasil dihapus.";
        }
        header("Location: index.php?tab=records");
        exit;
    } elseif ($action === 'resolv_local') {
        file_put_contents($resolvFile, "nameserver 127.0.0.1\n", LOCK_EX);
        $_SESSION['message'] = "DNS Resolver sistem VM berhasil diarahkan ke 127.0.0.1 (Localhost / dnsmasq).";
        header("Location: index.php?tab=system");
        exit;
    } elseif ($action === 'resolv_custom') {
        $customDns = trim($_POST['custom_dns'] ?? '');
        if (filter_var($customDns, FILTER_VALIDATE_IP)) {
            file_put_contents($resolvFile, "nameserver {$customDns}\n", LOCK_EX);
            $_SESSION['message'] = "DNS Resolver sistem VM berhasil diubah ke {$customDns}.";
        } else {
            $_SESSION['error'] = "Format IP DNS Resolver tidak valid!";
        }
        header("Location: index.php?tab=system");
        exit;
    } elseif ($action === 'restart_service') {
        shell_exec('systemctl restart dnsmasq');
        $_SESSION['message'] = "Layanan dnsmasq berhasil dimuat ulang (restarted).";
        header("Location: index.php?tab=system");
        exit;
    }
}

// Ambil notifikasi dari session
$message = $_SESSION['message'] ?? '';
$error = $_SESSION['error'] ?? '';
unset($_SESSION['message'], $_SESSION['error']);

// Data aktif
$records = parseDnsRecords($configFile);
$rawConfig = file_exists($configFile) ? file_get_contents($configFile) : '';
$rawResolv = file_exists($resolvFile) ? file_get_contents($resolvFile) : '';

$currentResolv = 'Tidak ditemukan';
if ($rawResolv) {
    preg_match_all('/^nameserver\s+([^\s]+)/m', $rawResolv, $mResolv);
    if (!empty($mResolv[1])) {
        $currentResolv = implode(', ', $mResolv[1]);
    }
}

$activeTab = $_GET['tab'] ?? 'records';
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Zone Editor (dnsmasq)</title>
    <style>
        :root {
            --bg-body: #f8fafc; --card-bg: #ffffff; --primary: #2563eb;
            --primary-hover: #1d4ed8; --text-dark: #0f172a; --text-muted: #64748b;
            --border: #e2e8f0;
            --badge-a: #dbeafe; --text-a: #1e40af;
            --badge-aaaa: #ede9fe; --text-aaaa: #5b21b6;
            --badge-cname: #fef3c7; --text-cname: #92400e;
            --badge-mx: #dcfce7; --text-mx: #166534;
            --badge-txt: #f1f5f9; --text-txt: #334155;
        }
        body { font-family: system-ui, -apple-system, sans-serif; background: var(--bg-body); color: var(--text-dark); margin: 0; padding: 24px; }
        .container { max-width: 1000px; margin: 0 auto; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 12px; }
        .header-actions { display: flex; gap: 10px; align-items: center; }
        .ip-badge { background: #e0f2fe; color: #0369a1; padding: 6px 14px; border-radius: 6px; font-size: 13px; font-weight: 600; border: 1px solid #bae6fd; }
        .status { background: #dcfce7; color: #15803d; padding: 6px 14px; border-radius: 999px; font-size: 13px; font-weight: bold; }
        
        /* Tab Navigasi */
        .tab-nav { display: flex; gap: 8px; border-bottom: 2px solid var(--border); margin-bottom: 20px; }
        .tab-btn { background: none; border: none; padding: 10px 18px; font-size: 14px; font-weight: 600; color: var(--text-muted); cursor: pointer; border-bottom: 3px solid transparent; margin-bottom: -2px; }
        .tab-btn:hover { color: var(--primary); }
        .tab-btn.active { color: var(--primary); border-bottom-color: var(--primary); }
        .tab-content { display: none; }
        .tab-content.active { display: block; }

        .card { background: var(--card-bg); border-radius: 8px; border: 1px solid var(--border); padding: 20px; margin-bottom: 20px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }
        .card-title { font-size: 15px; font-weight: 600; margin-top: 0; margin-bottom: 14px; }
        .form-grid { display: grid; grid-template-columns: 130px 1.5fr 1.5fr 90px auto; gap: 10px; align-items: end; }
        .field label { display: block; font-size: 12px; font-weight: 600; color: var(--text-muted); margin-bottom: 4px; }
        .field-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
        .field-header label { margin-bottom: 0; }
        .btn-link { background: none; border: none; color: var(--primary); font-size: 11px; cursor: pointer; text-decoration: underline; padding: 0; font-family: inherit; }
        input, select { width: 100%; padding: 8px 10px; border: 1px solid var(--border); border-radius: 6px; box-sizing: border-box; font-size: 14px; }
        button.btn-primary { background: var(--primary); color: #fff; border: none; padding: 9px 16px; border-radius: 6px; font-weight: 600; cursor: pointer; }
        button.btn-primary:hover { background: var(--primary-hover); }
        table { width: 100%; border-collapse: collapse; font-size: 14px; }
        th, td { padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); }
        th { background: #f8fafc; color: var(--text-muted); font-size: 12px; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 700; }
        .badge-A { background: var(--badge-a); color: var(--text-a); }
        .badge-AAAA { background: var(--badge-aaaa); color: var(--text-aaaa); }
        .badge-CNAME { background: var(--badge-cname); color: var(--text-cname); }
        .badge-MX { background: var(--badge-mx); color: var(--text-mx); }
        .badge-TXT { background: var(--badge-txt); color: var(--text-txt); border: 1px solid #cbd5e1; }
        .btn-del { background: #fee2e2; color: #b91c1c; border: none; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 12px; }
        pre { background: #0f172a; color: #38bdf8; padding: 14px; border-radius: 6px; font-family: monospace; font-size: 13px; margin: 0; overflow-x: auto; }
        .msg { padding: 10px; border-radius: 6px; margin-bottom: 15px; font-size: 14px; }
        .msg-success { background: #dcfce7; color: #166534; }
        .msg-error { background: #fee2e2; color: #991b1b; }
        .btn-action { display: inline-block; padding: 8px 14px; border-radius: 6px; font-size: 13px; font-weight: 600; text-decoration: none; border: none; cursor: pointer; }
        .btn-success { background: #059669; color: #fff; }
        .btn-warning { background: #d97706; color: #fff; }
        @media (max-width: 768px) {
            .form-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <div>
            <h2 style="margin:0 0 4px 0;">DNS Zone Editor</h2>
            <span style="color: var(--text-muted); font-size: 13px;">Pengaturan DNS Simulasi Lab Linux (dnsmasq)</span>
        </div>
        <div class="header-actions">
            <div class="ip-badge">
                DNS Server IP: <strong id="currentIp" style="font-family: monospace; font-size: 14px;"><?= htmlspecialchars($serverIp) ?></strong>
            </div>
            <div class="status">● dnsmasq Active</div>
        </div>
    </div>

    <!-- Navigasi Tab -->
    <div class="tab-nav">
        <button class="tab-btn <?= $activeTab === 'records' ? 'active' : '' ?>" onclick="switchTab('records')">📋 DNS Records</button>
        <button class="tab-btn <?= $activeTab === 'system' ? 'active' : '' ?>" onclick="switchTab('system')">⚙️ System Resolver</button>
    </div>

    <?php if ($message): ?><div class="msg msg-success"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <?php if ($error): ?><div class="msg msg-error"><?= htmlspecialchars($error) ?></div><?php endif; ?>

    <!-- TAB 1: DNS RECORDS -->
    <div id="tab-records" class="tab-content <?= $activeTab === 'records' ? 'active' : '' ?>">
        <div class="card">
            <div class="card-title">Tambah DNS Record</div>
            <form method="POST" class="form-grid">
                <input type="hidden" name="action" value="add">
                <div class="field">
                    <label>Tipe</label>
                    <select name="type" id="typeSelect" onchange="checkType()">
                        <option value="A">A (IPv4)</option>
                        <option value="AAAA">AAAA (IPv6)</option>
                        <option value="CNAME">CNAME (Alias)</option>
                        <option value="MX">MX (Mail)</option>
                        <option value="TXT">TXT (Text)</option>
                    </select>
                </div>
                <div class="field">
                    <label>Nama Domain</label>
                    <input type="text" name="domain" id="domainField" placeholder="web.sekolah.test" required>
                </div>
                <div class="field">
                    <div class="field-header">
                        <label id="targetLabel">IP Tujuan (IPv4)</label>
                        <button type="button" id="btnFillIp" class="btn-link" onclick="pasteServerIp()">Gunakan IP Server</button>
                    </div>
                    <input type="text" name="target" id="targetField" placeholder="192.168.100.10" required>
                </div>
                <div class="field">
                    <label>Prioritas</label>
                    <input type="number" name="priority" id="prioField" value="10" disabled>
                </div>
                <button type="submit" class="btn-primary">+ Simpan</button>
            </form>
        </div>

        <div class="card">
            <div class="card-title">Daftar Record Aktif</div>
            <table>
                <thead>
                    <tr>
                        <th style="width: 80px;">Tipe</th>
                        <th>Nama Host / Domain</th>
                        <th>Target / Nilai</th>
                        <th style="width: 80px;">Prioritas</th>
                        <th style="width: 60px;">Aksi</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($records)): ?>
                        <tr><td colspan="5" style="text-align:center; color: var(--text-muted);">Belum ada DNS record yang ditambahkan.</td></tr>
                    <?php else: ?>
                        <?php foreach ($records as $r): ?>
                            <tr>
                                <td><span class="badge badge-<?= $r['type'] ?>"><?= $r['type'] ?></span></td>
                                <td><strong><?= htmlspecialchars($r['domain']) ?></strong></td>
                                <td style="word-break: break-all;"><?= htmlspecialchars($r['target']) ?></td>
                                <td><?= htmlspecialchars($r['priority']) ?></td>
                                <td>
                                    <form method="POST" onsubmit="return confirm('Hapus record ini?');" style="margin:0;">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="id" value="<?= $r['id'] ?>">
                                        <button type="submit" class="btn-del">Hapus</button>
                                    </form>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>

        <div class="card">
            <div class="card-title">Isi Berkas: <code>/etc/dnsmasq.d/custom_records.conf</code></div>
            <pre><?= htmlspecialchars($rawConfig) ?: '# Belum ada konfigurasi' ?></pre>
        </div>
    </div>

    <!-- TAB 2: SYSTEM RESOLVER & OPSI -->
    <div id="tab-system" class="tab-content <?= $activeTab === 'system' ? 'active' : '' ?>">
        <div class="card">
            <div class="card-title">DNS Resolver Sistem VM (<code>/etc/resolv.conf</code>)</div>
            <p style="font-size: 13px; color: var(--text-muted); margin-top: 0;">
                Nameserver yang tercantum di sini digunakan oleh sistem operasi VM (termasuk CloudPanel & Nginx) untuk menyelesaikan nama domain.
            </p>
            <div style="background: #f1f5f9; padding: 12px; border-radius: 6px; margin-bottom: 16px; font-size: 14px;">
                Nameserver Aktif: <strong style="color: #0f172a;"><?= htmlspecialchars($currentResolv) ?></strong>
            </div>

            <div style="display: flex; gap: 10px; align-items: center; flex-wrap: wrap;">
                <!-- Shortcut 127.0.0.1 -->
                <form method="POST" style="margin: 0;">
                    <input type="hidden" name="action" value="resolv_local">
                    <button type="submit" class="btn-action btn-success">
                        ⚡ Set ke 127.0.0.1 (Mode Offline Lab)
                    </button>
                </form>

                <!-- Input Custom DNS -->
                <form method="POST" style="display: flex; gap: 8px; margin: 0; align-items: center;">
                    <input type="hidden" name="action" value="resolv_custom">
                    <input type="text" name="custom_dns" placeholder="Contoh: 1.1.1.1" style="width: 150px; padding: 8px;" required>
                    <button type="submit" class="btn-action" style="background: #334155; color: #fff;">Simpan DNS</button>
                </form>
            </div>
        </div>

        <div class="card">
            <div class="card-title">Kontrol Layanan dnsmasq</div>
            <p style="font-size: 13px; color: var(--text-muted); margin-top: 0;">
                Muat ulang proses daemon dnsmasq jika ada perubahan konfigurasi manual di terminal.
            </p>
            <form method="POST" style="margin: 0;">
                <input type="hidden" name="action" value="restart_service">
                <button type="submit" class="btn-action btn-warning">🔄 Restart dnsmasq Service</button>
            </form>
        </div>

        <div class="card">
            <div class="card-title">Isi Berkas: <code>/etc/resolv.conf</code></div>
            <pre><?= htmlspecialchars($rawResolv) ?: '# Berkas kosong' ?></pre>
        </div>
    </div>
</div>

<script>
function switchTab(tabName) {
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

    if (tabName === 'system') {
        document.querySelectorAll('.tab-btn')[1].classList.add('active');
        document.getElementById('tab-system').classList.add('active');
    } else {
        document.querySelectorAll('.tab-btn')[0].classList.add('active');
        document.getElementById('tab-records').classList.add('active');
    }
    history.replaceState(null, '', '?tab=' + tabName);
}

function pasteServerIp() {
    const serverIp = document.getElementById('currentIp').innerText;
    document.getElementById('targetField').value = serverIp;
}

function checkType() {
    const t = document.getElementById('typeSelect').value;
    const prio = document.getElementById('prioField');
    const label = document.getElementById('targetLabel');
    const target = document.getElementById('targetField');
    const btnFillIp = document.getElementById('btnFillIp');
    
    if (t === 'MX') {
        prio.disabled = false;
        label.innerText = 'Mail Server';
        target.placeholder = 'mail.sekolah.test';
        btnFillIp.style.display = 'none';
    } else if (t === 'CNAME') {
        prio.disabled = true;
        label.innerText = 'Domain Asal';
        target.placeholder = 'sekolah.test';
        btnFillIp.style.display = 'none';
    } else if (t === 'AAAA') {
        prio.disabled = true;
        label.innerText = 'IP Tujuan (IPv6)';
        target.placeholder = '2001:db8::10';
        btnFillIp.style.display = 'none';
    } else if (t === 'TXT') {
        prio.disabled = true;
        label.innerText = 'Nilai / Nilai SPF';
        target.placeholder = 'v=spf1 a mx ~all';
        btnFillIp.style.display = 'none';
    } else {
        prio.disabled = true;
        label.innerText = 'IP Tujuan (IPv4)';
        target.placeholder = '192.168.100.10';
        btnFillIp.style.display = 'inline';
    }
}
</script>
</body>
</html>
EOF

# 5. Pasang systemd service pada port 1919
echo "[*] Mendaftarkan systemd service (dns-ui.service) pada port 1919..."
cat << EOF > /etc/systemd/system/dns-ui.service
[Unit]
Description=DNS Zone Editor Web Service
After=network.target dnsmasq.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/php -S 0.0.0.0:1919 -t ${APP_DIR}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 6. Muat ulang daemon dan jalankan service
echo "[*] Mengaktifkan dan menjalankan service..."
systemctl daemon-reload
systemctl enable --now dns-ui.service
systemctl restart dnsmasq

# Dapatkan IP interface
IP_ADDR=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================================="
echo " [V] Instalasi Berhasil!"
echo "=========================================================="
echo " Layanan Web DNS Manager berjalan pada port 1919."
echo " DNS Server IP : ${IP_ADDR}"
echo " Akses Browser : http://${IP_ADDR}:1919"
echo "=========================================================="
