#!/bin/sh
# Auto-generate the patched vendor readers from the camera's OWN firmware.
# We ship NO proprietary binary: the base is /opt/ipnc/demo (miSafes/InfoTM,
# present on every D304). We only apply small byte-diffs (our RTSP patches):
#   demo_dump  = SHM video reader  + 2ms poll-sleep (anti busy-spin)
#   demo_audio = SHM audio reader  + 2ms poll-sleep
#   demo_se0   = enable HW HEVC stream 0 (720p) via avserver IPC 0xcf
BB=/mnt/mmc/busybox-armv7l
SRC=/opt/ipnc/demo
DST=/mnt/mmc
BASE_MD5="1be10bf7c0127b5e033dab4ec0163672"

md5of() { $BB md5sum "$1" 2>/dev/null | $BB awk '{print $1}'; }
apply() { echo "$3" | $BB base64 -d | $BB dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null; }

# idempotent: if all three already correct, skip
if ! ( [ "$(md5of $DST/demo_dump)" != "d0a25b6338ecf871e26507d5159d9701" ] || [ "$(md5of $DST/demo_audio)" != "129f1de6bb2810ed27f7a140a56e27f3" ] || [ "$(md5of $DST/demo_se0)" != "2bba074678577dc6d497897b37312d59" ] ); then echo "demo_* already patched"; exit 0; fi

if [ ! -f "$SRC" ]; then echo "FATAL: $SRC not found (not a D304 / different firmware)"; exit 1; fi
SRCMD5=$(md5of "$SRC")
if [ "$SRCMD5" != "$BASE_MD5" ]; then echo "FATAL: /opt/ipnc/demo md5 $SRCMD5 != expected $BASE_MD5 (firmware differs; patch offsets unsafe)"; exit 1; fi

# ---- demo_dump (5 runs) ----
$BB cp "$SRC" "$DST/demo_dump"
apply "$DST/demo_dump" 13846 ASAAvw==
apply "$DST/demo_dump" 14074 EPDIvA==
apply "$DST/demo_dump" 16428 T/b/ccf2/3H/99C6
apply "$DST/demo_dump" 82062 Len/XwIg9Pcs/r3o/18=
apply "$DST/demo_dump" 82077 LgHd7/fWuu/3K7s=
$BB chmod 755 "$DST/demo_dump"
M=$(md5of "$DST/demo_dump")
if [ "$M" != "d0a25b6338ecf871e26507d5159d9701" ]; then echo "FATAL: demo_dump built md5 $M != d0a25b6338ecf871e26507d5159d9701"; exit 1; fi
echo "demo_dump OK (d0a25b6338ecf871e26507d5159d9701)"

# ---- demo_audio (7 runs) ----
$BB cp "$SRC" "$DST/demo_audio"
apply "$DST/demo_audio" 13846 ASAAvw==
apply "$DST/demo_audio" 13906 EA==
apply "$DST/demo_audio" 13908 HP0=
apply "$DST/demo_audio" 13920 7/w=
apply "$DST/demo_audio" 14070 pA==
apply "$DST/demo_audio" 17180 AyBP9v9xx/b/cf/3V7k=
apply "$DST/demo_audio" 82062 Len/XwIg9Pcs/r3o/58=
$BB chmod 755 "$DST/demo_audio"
M=$(md5of "$DST/demo_audio")
if [ "$M" != "129f1de6bb2810ed27f7a140a56e27f3" ]; then echo "FATAL: demo_audio built md5 $M != 129f1de6bb2810ed27f7a140a56e27f3"; exit 1; fi
echo "demo_audio OK (129f1de6bb2810ed27f7a140a56e27f3)"

# ---- demo_se0 (3 runs) ----
$BB cp "$SRC" "$DST/demo_se0"
apply "$DST/demo_se0" 11260 Ag==
apply "$DST/demo_se0" 11264 QPLPA0DyABA=
apply "$DST/demo_se0" 11276 rfgcAA==
$BB chmod 755 "$DST/demo_se0"
M=$(md5of "$DST/demo_se0")
if [ "$M" != "2bba074678577dc6d497897b37312d59" ]; then echo "FATAL: demo_se0 built md5 $M != 2bba074678577dc6d497897b37312d59"; exit 1; fi
echo "demo_se0 OK (2bba074678577dc6d497897b37312d59)"

echo "BOOTSTRAP_DEMO_DONE"
