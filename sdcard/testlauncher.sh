#!/bin/sh
###############################################################################
# testlauncher.sh -- miSafes D304 (InfoTM iMAPx15 / Broadcom AP6212)
#   WiFi 自動接続 + 単色LEDステータス + telnetd + dropbear(SSH)
#
#   同梱物 (microSD ルート, LF改行):
#     testlauncher.sh   このスクリプト
#     busybox-armv7l    フル busybox
#     dropbear          静的ARM dropbearmulti (SSHサーバ)
#     authorized_keys   自分の公開鍵(RSA)  ※ed25519はdropbear非対応
#
#   接続後:  ssh -i ~/.ssh/id_rsa root@<カメラIP>      (pubkeyのみ)
#            telnet <カメラIP>                          (フォールバック)
#
#   LED: /sys/class/leds/led/brightness の値は色+点滅パターンのコード:
#          0=消灯  30=青点滅  40=緑点滅  50=赤点滅   (solid点灯は無し)
#        接続処理中=青(30) / 成功=緑(40) / 失敗=赤(50)
###############################################################################

###############################################################################
#  ★★ 自動起動サービス選択 ★★   下の番号を書き換えるだけ:
#      0 = なし
#      1 = Caddy    (Web サーバ       http://<IP>:8080   docroot=/mnt/mmc)
#      2 = Cuberite (Minecraft 鯖      <IP>:25565)
#      3 = Camera   (防犯カメラ・生視聴 http://<IP>:8080/  ※avserver+Java+Caddy)
#      4 = RTSP     (HW H.265 配信      rtsp://<IP>:8554/cam  ※avserver+go2rtc+ffmpeg)
###############################################################################
APP_SELECT=4
###############################################################################

################################  設定  #######################################
# --- WiFi 認証情報は secrets.conf に分離 (git 管理外) --------------------------
#   SD 直下 (/mnt/mmc/secrets.conf) に  SSID="..."  PSK="..."  を書くと読み込む。
#   無ければ下記プレースホルダのまま (WiFi には繋がらない)。secrets.conf.example 参照。
SSID="YOUR_WIFI_SSID"
PSK="YOUR_WIFI_PASSWORD"
[ -f /mnt/mmc/secrets.conf ] && . /mnt/mmc/secrets.conf
IFACE="wlan0"
# --- IPアドレス設定 : 固定にするなら STATIC_IP="yes" ------------------------
STATIC_IP="no"                 # "yes"=固定IP / "no"=DHCP(自動取得)
STATIC_ADDR="192.168.10.50"    # 固定したいIPアドレス (STATIC_IP="yes" のとき使用)
STATIC_MASK="255.255.255.0"    # サブネットマスク
STATIC_GW="192.168.10.1"       # デフォルトゲートウェイ(ルータのIP)
STATIC_DNS="192.168.10.1"      # DNSサーバ(通常はゲートウェイと同じでOK/NTP時刻同期に使用)
# ---------------------------------------------------------------------------
WIFIDIR="/wifi/broadcom_ap6212"
CONF="/tmp/wpa_supplicant.conf"
USCRIPT="/tmp/udhcpc.script"
LOG="/mnt/mmc/wifi_result.txt"
LED="/sys/class/leds/led/brightness"
LED_OFF=0
LED_BLUE=30
LED_GREEN=40
LED_RED=50
ASSOC_TIMEOUT=30
BB="/bin/busybox"
SDBB="/mnt/mmc/busybox-armv7l"
DROPBEAR="/mnt/mmc/dropbear"
AKEYS="/mnt/mmc/authorized_keys"
HK_SD="/mnt/mmc/dropbear_rsa_host_key"   # host鍵を永続化(ssh警告防止)
SSHLOG="/mnt/mmc/ssh_log.txt"
# --- 自動起動アプリのパス ---
CADDY="/mnt/mmc/caddy"                    # Caddy 本体
CUBEDIR="/mnt/mmc/cuberite"               # Cuberite 一式
GL3="/mnt/mmc/gl3"                        # glibc2.31 ランタイム(Cuberite用)
# --- 防犯カメラモード用 ---
GL2="/mnt/mmc/gl2"                        # glibc2.27 ランタイム(Java用/loader同梱)
JRE="/mnt/mmc/jre/jdk8u492-b09-aarch32-20260428-jre"   # ARM Java 8
LIVECLS="/mnt/mmc"                        # Live.class の -cp
FRAMEPHYS="0x4e9ae000"                    # Felix ISP フレームバッファ物理アドレス
LIVEJPG="/mnt/mmc/live.jpg"               # 圧縮JPEG出力(Caddyが配信)
CAM_W=480; CAM_H=270; CAM_Q=60            # ライブ解像度/JPEG品質(小さいほど高fps。例320x180 q55=~4fps)
###############################################################################

led() { echo "$1" > "$LED" 2>/dev/null; }
log() { echo "[$($BB date +%H:%M:%S 2>/dev/null)] $1" >> "$LOG"; sync; }

###############################################################################
# コマンドを素の名前で使えるようにする:
#   SD の多機能 busybox の全 applet を tmpfs(/tmp/xbin) に symlink して PATH 化。
#   併せて DNS 用に /etc/resolv.conf -> /tmp/resolv.conf を張る。
###############################################################################
setup_env() {
    chmod +x "$SDBB" 2>/dev/null
    mkdir -p /tmp/xbin 2>/dev/null
    for a in $("$SDBB" --list 2>/dev/null); do
        ln -sf "$SDBB" /tmp/xbin/"$a" 2>/dev/null
    done
    # DNS: /etc/resolv.conf が無ければ /tmp/resolv.conf へリンク(rwに一度だけ)
    if [ ! -e /etc/resolv.conf ]; then
        mount -o remount,rw / 2>/dev/null
        ln -sf /tmp/resolv.conf /etc/resolv.conf 2>/dev/null
        mount -o remount,ro / 2>/dev/null
    fi
    log "setup_env: /tmp/xbin ready ($(ls /tmp/xbin 2>/dev/null | wc -l) applets)"
}

###############################################################################
# NTP時刻同期: カメラOSDタイムスタンプ/録画名/ログの時刻を正しくする
#   (WiFi接続後・アプリ起動前に呼ぶ)
###############################################################################
sync_time() {
    for s in pool.ntp.org time.google.com ntp.nict.jp; do
        "$SDBB" ntpd -nq -p "$s" >/dev/null 2>&1 && { log "time synced via $s: $($BB date 2>/dev/null)"; return 0; }
    done
    log "NTP sync failed (time stays default)"
    return 1
}

###############################################################################
# telnetd (無認証 root シェル, フォールバック)
###############################################################################
start_telnet() {
    chmod +x "$SDBB" 2>/dev/null
    [ -d /dev/pts ] || { mkdir -p /dev/pts 2>/dev/null; mount -t devpts none /dev/pts 2>/dev/null; }
    "$SDBB" telnetd -l /bin/sh -p 23 2>/dev/null || $BB telnetd -l /bin/sh 2>/dev/null
    log "telnetd started (port 23)"
}

###############################################################################
# dropbear (SSH, 公開鍵認証のみ)
#   rootfs は read-only の為 authorized_keys は tmpfs に厳格permで置き、
#   root のホームへ bind mount して dropbear に読ませる。
###############################################################################
start_ssh() {
    [ -f "$DROPBEAR" ] || { log "SSH skip: $DROPBEAR not found"; return 1; }
    [ -f "$AKEYS" ]    || { log "SSH skip: $AKEYS not found";    return 1; }
    chmod +x "$DROPBEAR" 2>/dev/null

    # root ホーム検出('/' は危険なので /root に矯正)
    RHOME=$($BB awk -F: '$1=="root"{print $6}' /etc/passwd 2>/dev/null)
    [ -z "$RHOME" ] && RHOME=/root
    [ "$RHOME" = "/" ] && RHOME=/root

    # authorized_keys を tmpfs に厳格permで用意
    mkdir -p /tmp/dbhome/.ssh 2>/dev/null
    cp "$AKEYS" /tmp/dbhome/.ssh/authorized_keys 2>/dev/null
    chmod 700 /tmp/dbhome /tmp/dbhome/.ssh 2>/dev/null
    chmod 600 /tmp/dbhome/.ssh/authorized_keys 2>/dev/null
    # SSHログイン(login shell)時に PATH を自動設定 (~/.profile を読む)
    printf 'export PATH=/tmp/xbin:$PATH\n' > /tmp/dbhome/.profile 2>/dev/null

    # home が無ければ一時的に rw remount して作成(空ディレクトリのみ)
    if [ ! -d "$RHOME" ]; then
        mount -o remount,rw / 2>/dev/null
        mkdir -p "$RHOME" 2>/dev/null
        mount -o remount,ro / 2>/dev/null
    fi
    mount -o bind /tmp/dbhome "$RHOME" 2>/dev/null

    # host鍵: SDに保存済みならコピー、無ければ dropbearkey(multi内蔵)で明示生成
    #   ※ -R 自動生成に頼らず確実に用意する
    HK=/tmp/dropbear_rsa_host_key
    if [ -f "$HK_SD" ]; then
        cp "$HK_SD" "$HK" 2>/dev/null; chmod 600 "$HK" 2>/dev/null
    else
        ln -sf "$DROPBEAR" /tmp/dropbearkey 2>/dev/null
        /tmp/dropbearkey -t rsa -f "$HK" >/dev/null 2>>"$SSHLOG"
        cp "$HK" "$HK_SD" 2>/dev/null; sync
    fi

    # -s: パスワード認証無効(pubkeyのみ) / -p 22
    "$DROPBEAR" -s -r "$HK" -p 22 -P /tmp/dropbear.pid 2>> "$SSHLOG" &
    sleep 2
    log "dropbear(ssh) launch attempted (see $SSHLOG)"
    log "dropbear(ssh) started on :22  home=$RHOME"
}
###############################################################################

###############################################################################
# 自動起動アプリ (先頭の APP_SELECT で選択)
###############################################################################
start_caddy() {
    [ -f "$CADDY" ] || { log "Caddy skip: $CADDY not found"; return 1; }
    chmod +x "$CADDY" 2>/dev/null
    XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy \
        "$CADDY" file-server --root /mnt/mmc --listen :8080 --browse \
        </dev/null > /mnt/mmc/caddy.log 2>&1 &
    echo $! > /tmp/caddy.pid
    log "Caddy started :8080 root=/mnt/mmc (pid $(cat /tmp/caddy.pid))"
}

start_cuberite() {
    [ -x "$CUBEDIR/Cuberite" ] || { log "Cuberite skip: $CUBEDIR/Cuberite not found"; return 1; }
    # glibc ローダを短パスへ (Cuberite の ELF interp は /tmp/ld にパッチ済み)
    cp "$GL3/ld-linux-armhf.so.3" /tmp/ld 2>/dev/null; chmod +x /tmp/ld 2>/dev/null
    # stdin を開いたまま保つ FIFO (EOF=stop 誤検知を防ぐ)。コマンド送信は echo ... > /tmp/cubein
    [ -p /tmp/cubein ] || mkfifo /tmp/cubein 2>/dev/null
    ( while : ; do sleep 3600; done ) > /tmp/cubein &
    echo $! > /tmp/cubefeeder.pid
    cd "$CUBEDIR" || return 1
    LD_LIBRARY_PATH="$GL3" ./Cuberite < /tmp/cubein > "$CUBEDIR/cube.log" 2>&1 &
    echo $! > /tmp/cube.pid
    cd / 2>/dev/null
    log "Cuberite started :25565 (pid $(cat /tmp/cube.pid))"
}

# --- 防犯カメラ: avserver(ISP) -> Java が /dev/mem のフレームをJPEG圧縮 -> Caddy配信 ---
start_camera() {
    [ -f "$LIVECLS/Live.class" ] || { log "Camera skip: Live.class not found"; return 1; }
    [ -x "$JRE/bin/java" ]       || { log "Camera skip: JRE not found";        return 1; }
    # Java用 glibc2.27 ローダを /tmp/ld へ (java の ELF interp は /tmp/ld にパッチ済み)
    cp "$GL2/ld-linux-armhf.so.3" /tmp/ld 2>/dev/null; chmod +x /tmp/ld 2>/dev/null
    # 1) avserver: ISP がフレームを /dev/mem に生成 (録画はしない)
    /opt/ipnc/avserver_q3.bin </dev/null >/tmp/av.log 2>&1 &
    echo $! > /tmp/av.pid
    # SSH(管理用)を最優先・重い処理を低優先度に (camera時もSSHで入れるように)
    renice -20 -p "$(cat /tmp/dropbear.pid 2>/dev/null)" 2>/dev/null
    renice 15 -p "$(cat /tmp/av.pid)" 2>/dev/null
    # 2) Caddy を先に起動 (:8080 で index.html(生視聴ページ) と live.jpg を配信)
    XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy \
        "$CADDY" file-server --root /mnt/mmc --listen :8080 </dev/null >/mnt/mmc/caddy.log 2>&1 &
    echo $! > /tmp/caddy.pid
    sleep 18   # ISP パイプライン起動待ち
    # 3) Java: フレーム読出→640x362グレースケールJPEG(アトミック更新)ループ
    LD_LIBRARY_PATH="$GL2:$JRE/lib/aarch32:$JRE/lib/aarch32/jli:$JRE/lib/aarch32/server" \
        "$JRE/bin/java" -Xmx48M -Djava.awt.headless=true -cp "$LIVECLS" Live "$FRAMEPHYS" "$CAM_W" "$CAM_H" "$CAM_Q" "$LIVEJPG" 0 \
        </dev/null >/tmp/live.log 2>&1 &
    echo $! > /tmp/live.pid
    renice 10 -p "$(cat /tmp/live.pid)" 2>/dev/null
    log "Camera mode on :8080  http://<IP>:8080/  (av=$(cat /tmp/av.pid) java=$(cat /tmp/live.pid))"
}

# --- RTSP: avserver(ISP+HW H.265) -> demo_dump/demo_audio が SHM の HEVC+G711 を取り出し
#         -> ffmpeg が copy で RTSP publish -> go2rtc が rtsp://<IP>:8554/cam で常時配信 ---
#   汎用の防犯カメラアプリ/VLC/ffplay から  rtsp://<IP>:8554/cam で
#   HW H.265(720p カラー) + G711 音声(PCMA) を視聴。音声・映像とも無変換(copy)で軽量。
#   常時パブリッシュ方式: ffmpeg を1本だけ常駐させ go2rtc に流し込む(接続即再生・リーク無し)。
start_rtsp() {
    # 初回起動時: カメラ自身のファーム /opt/ipnc/demo から patched リーダを生成
    #   (demo_dump/demo_audio/demo_se0)。独自バイナリを同梱しないための仕組み。
    #   既に生成済みなら即 return する冪等スクリプト。詳細は bootstrap_demo.sh。
    if [ -x /mnt/mmc/bootstrap_demo.sh ] || [ -f /mnt/mmc/bootstrap_demo.sh ]; then
        /bin/sh /mnt/mmc/bootstrap_demo.sh >/mnt/mmc/bootstrap_demo.log 2>&1
    fi
    [ -x /mnt/mmc/go2rtc ]     || { log "RTSP skip: go2rtc not found";    return 1; }
    [ -x /mnt/mmc/ffmpeg ]     || { log "RTSP skip: ffmpeg not found";    return 1; }
    [ -x /mnt/mmc/demo_se0 ]   || { log "RTSP skip: demo_se0 not found";  return 1; }
    [ -x /mnt/mmc/demo_dump ]  || { log "RTSP skip: demo_dump not found"; return 1; }
    [ -f /mnt/mmc/pub_video.sh ]|| { log "RTSP skip: pub_video.sh not found"; return 1; }
    [ -f /mnt/mmc/pub_audio.sh ]|| { log "RTSP skip: pub_audio.sh not found"; return 1; }
    # 0) ループバックを立てる: ffmpeg が go2rtc(127.0.0.1:8554) へ publish するのに必須
    #    (このカメラは既定で lo が未設定。無いと publish 接続がハングする)
    "$SDBB" ifconfig lo 127.0.0.1 netmask 255.0.0.0 up 2>/dev/null
    # 0.5) 死んだ miSafes/qiwo クラウド系デーモンを止める。単核CPUで p2ptutk(P2P) や
    #    qiwocloud1 への setVideoFile アップロード(curl)が回り続け、idle 0% まで
    #    飽和させてHWエンコーダを餓死させていた(kill後 idle 0%->66%, fps 3->9)。
    #    sysserver が再生成しうるので 30 秒毎に掃除する軽量ウォッチドッグにする。
    ( while true; do
        for n in p2ptutk app_qiwo bsa_server; do "$SDBB" killall -9 "$n" 2>/dev/null; done
        for p in $(ps | "$SDBB" grep -E 'qiwocloud|setVideoFile' | "$SDBB" grep -v grep | "$SDBB" awk '{print $1}'); do "$SDBB" kill -9 "$p" 2>/dev/null; done
        "$SDBB" sleep 30
      done ) &
    echo $! > /tmp/killcloud.pid
    # 1) avserver: ISP + HW HEVC エンコーダ (vendor sysserver が起動済みなら再利用)
    if ! pidof avserver_q3.bin >/dev/null 2>&1; then
        /opt/ipnc/avserver_q3.bin </dev/null >/tmp/av.log 2>&1 &
        echo $! > /tmp/av.pid
    fi
    # 管理SSHを最優先 (単核CPUでもSSHが細らないように)
    renice -20 -p "$(cat /tmp/dropbear.pid 2>/dev/null)" 2>/dev/null
    sleep 18   # ISP パイプライン起動待ち
    # 2) HW HEVC ストリーム0(720p) を有効化 (avserver への IPC cmd 0xcf / mtype 2)
    #    ※ demo_se0 は IPC 送信後に応答待ちでブロックするので、送出させてから停止する(ハング防止)
    /mnt/mmc/demo_se0 102 </dev/null >/dev/null 2>&1 &
    _sepid=$!
    sleep 3
    kill "$_sepid" 2>/dev/null
    # 3) go2rtc: cam を空定義(publish 受け口)にした go2rtc.yaml で起動
    cd /mnt/mmc
    /mnt/mmc/go2rtc -config /mnt/mmc/go2rtc.yaml </dev/null >/mnt/mmc/go2rtc.log 2>&1 &
    echo $! > /tmp/go2rtc.pid
    cd / 2>/dev/null
    sleep 3
    # 4) 常時パブリッシャ (映像/音声 分離方式)。
    #    単一 ffmpeg で A/V を mux すると、muxer が音声待ちで映像を保持し fps が激落ち
    #    (3fps)。映像専用 ffmpeg と音声専用 ffmpeg を別々に go2rtc /cam へ publish し、
    #    go2rtc 側で 2 producer のトラックを 1 本の cam に統合する(=9fps へ改善)。
    #    各ループは自分のリーダ(demo_dump / demo_audio)だけを killall するので相互干渉なし。
    ( while true; do
        /bin/sh /mnt/mmc/pub_video.sh 11 </dev/null >/tmp/pub_video.log 2>&1
        sleep 3
      done ) &
    echo $! > /tmp/pub_video.pid
    sleep 2
    ( while true; do
        /bin/sh /mnt/mmc/pub_audio.sh </dev/null >/tmp/pub_audio.log 2>&1
        sleep 3
      done ) &
    echo $! > /tmp/pub_audio.pid
    log "RTSP mode on :8554  rtsp://<IP>:8554/cam  (HW H.265 720p + G711 audio, go2rtc pid $(cat /tmp/go2rtc.pid 2>/dev/null))"
}

start_app() {
    case "$APP_SELECT" in
        1) log "APP_SELECT=1 -> Caddy";    start_caddy ;;
        2) log "APP_SELECT=2 -> Cuberite"; start_cuberite ;;
        3) log "APP_SELECT=3 -> Camera";   start_camera ;;
        4) log "APP_SELECT=4 -> RTSP";     start_rtsp ;;
        *) log "APP_SELECT=$APP_SELECT -> no app autostart" ;;
    esac
}
###############################################################################


##############################  メイン  #######################################
echo "=== miSafes D304 wifi connect log ===" > "$LOG"; sync

# --- コマンド環境(applet symlink farm + DNS) --------------------------------
setup_env

# --- Enable HW camera encoder (RTSP mode, APP_SELECT=4) ----------------------
# Per PIGYO's miSafes D304 analysis: the registration files (reg_info_file /
# guid_file*), which a factory reset wipes, enable the HW H.265 loop-recording
# encoder. avserver must initialise a FRESH ISP (else felix init fails), so it
# is launched early here, before WiFi. (ASCII comment on purpose - keep it.)
if [ "$APP_SELECT" = "4" ]; then
    mount -w -o remount / 2>/dev/null
    [ -f /mnt/config/reg_info_file ] || touch /mnt/config/reg_info_file
    [ -f /mnt/config/guid_file ]     || echo 1111111111AAAAAAAAAA > /mnt/config/guid_file
    [ -f /mnt/config/guid_file_pwd ] || echo a8888888 > /mnt/config/guid_file_pwd
    if ! pidof avserver_q3.bin >/dev/null 2>&1; then
        /opt/ipnc/avserver_q3.bin </dev/null >/tmp/av.log 2>&1 &
        echo $! > /tmp/av.pid
    fi
fi

# --- LED 自己テスト: 青→緑→赤 ------------------------------------------------
led "$LED_BLUE";  sleep 1
led "$LED_GREEN"; sleep 1
led "$LED_RED";   sleep 1
led "$LED_OFF"
# --- 接続処理中 = 青点滅 -----------------------------------------------------
led "$LED_BLUE"

# --- wpa_supplicant.conf -----------------------------------------------------
cat > "$CONF" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
ap_scan=1

network={
    scan_ssid=1
    ssid="$SSID"
    key_mgmt=WPA-PSK
    psk="$PSK"
}
EOF
chmod 600 "$CONF" 2>/dev/null
log "conf written for SSID=$SSID"

# --- udhcpc script -----------------------------------------------------------
cat > "$USCRIPT" <<'USCR'
#!/bin/sh
BB=/bin/busybox
case "$1" in
    deconfig)
        $BB ifconfig $interface 0.0.0.0
        ;;
    bound|renew)
        $BB ifconfig $interface $ip netmask ${subnet:-255.255.255.0}
        [ -n "$router" ] && $BB route add default gw $router dev $interface 2>/dev/null
        echo "$ip"     > /tmp/wan_ip
        echo "$router" > /tmp/wan_gw
        : > /tmp/resolv.conf
        for d in $dns; do echo "nameserver $d" >> /tmp/resolv.conf; done
        ;;
esac
USCR
chmod +x "$USCRIPT"

# --- wlan0 up + wpa_supplicant ----------------------------------------------
log "ifconfig $IFACE up"
$BB ifconfig "$IFACE" up 2>/dev/null
log "start wpa_supplicant (nl80211)"
"$WIFIDIR/wpa_supplicant" -Dnl80211 -i"$IFACE" -c"$CONF" &
sleep 3

# --- association 待ち (失敗時は wpa_cli reassociate で最大3回リトライ) --------
#   このカメラのWiFi(AP6212)は間欠的に一発でassociationしないことがある。
#   その場合 wpa_supplicant はそのままに再接続を促す(未接続でのブート放置を防ぐ)。
assoc=0; try=0
while [ "$try" -lt 3 ] && [ "$assoc" = "0" ]; do
    try=$((try + 1))
    [ "$try" -gt 1 ] && { log "wifi reassociate (try $try)"; "$WIFIDIR/wpa_cli" -i "$IFACE" reassociate 2>/dev/null; sleep 2; }
    i=0
    while [ "$i" -lt "$ASSOC_TIMEOUT" ]; do
        "$WIFIDIR/wpa_cli" -i "$IFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED" && { assoc=1; break; }
        sleep 1; i=$((i + 1))
    done
    log "wifi try $try: assoc=$assoc (${i}s)"
done

# --- IP取得: 固定IP or DHCP --------------------------------------------------
if [ "$assoc" = "1" ]; then
    if [ "$STATIC_IP" = "yes" ]; then
        log "static IP: $STATIC_ADDR netmask $STATIC_MASK gw $STATIC_GW dns $STATIC_DNS"
        $BB ifconfig "$IFACE" "$STATIC_ADDR" netmask "$STATIC_MASK" up
        [ -n "$STATIC_GW" ] && $BB route add default gw "$STATIC_GW" dev "$IFACE" 2>/dev/null
        echo "$STATIC_ADDR" > /tmp/wan_ip
        echo "$STATIC_GW"   > /tmp/wan_gw
        : > /tmp/resolv.conf
        [ -n "$STATIC_DNS" ] && echo "nameserver $STATIC_DNS" >> /tmp/resolv.conf
    else
        log "udhcpc start"
        /sbin/udhcpc -i "$IFACE" -s "$USCRIPT" -t 15 -T 2 -n -q >> "$LOG" 2>&1
        log "udhcpc returned rc=$?"
    fi
fi

# --- IP 確認 -----------------------------------------------------------------
IP=$($BB ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
# associationはできたが DHCP が IP を取れなかった場合、静的IPで救済してブートを続行
if [ -z "$IP" ] && [ "$assoc" = "1" ] && [ "$STATIC_IP" != "yes" ]; then
    log "DHCP failed -> static fallback $STATIC_ADDR"
    $BB ifconfig "$IFACE" "$STATIC_ADDR" netmask "$STATIC_MASK" up
    [ -n "$STATIC_GW" ] && $BB route add default gw "$STATIC_GW" dev "$IFACE" 2>/dev/null
    echo "$STATIC_ADDR" > /tmp/wan_ip
    echo "$STATIC_GW"   > /tmp/wan_gw
    : > /tmp/resolv.conf
    [ -n "$STATIC_DNS" ] && echo "nameserver $STATIC_DNS" >> /tmp/resolv.conf
    IP=$($BB ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
fi
[ -n "$IP" ] && connected=1 || connected=0

# --- 結果 --------------------------------------------------------------------
if [ "$connected" = "1" ]; then
    led "$LED_GREEN"                    # 成功: 緑点滅
    GW=$(cat /tmp/wan_gw 2>/dev/null)
    log "SUCCESS  ip=$IP  gw=$GW"
    start_telnet
    start_ssh
    sync_time                           # NTP時刻同期(カメラOSD/録画名/ログの時刻を正しく)
    start_app                           # ← 先頭 APP_SELECT に応じて Caddy/Cuberite/Camera を起動
    if [ -n "$GW" ]; then
        log "ping gw $GW"
        $BB ping -c 3 -W 2 "$GW" >> "$LOG" 2>&1
    fi
    { echo "--- ifconfig ---"; $BB ifconfig "$IFACE" 2>&1; } >> "$LOG"; sync
    log "READY:  ssh -i ~/.ssh/id_rsa root@$IP   |   telnet $IP"
    while : ; do led "$LED_GREEN"; sleep 30; done
else
    led "$LED_RED"                      # 失敗: 赤点滅
    log "FAILED  (assoc=$assoc, no IP)"
    { echo "--- wpa_cli status ---"; "$WIFIDIR/wpa_cli" -i "$IFACE" status 2>&1; } >> "$LOG"; sync
    while : ; do led "$LED_RED"; sleep 30; done
fi
