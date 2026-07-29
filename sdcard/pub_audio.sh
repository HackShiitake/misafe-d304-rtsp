#!/bin/sh
B=/mnt/mmc/busybox-armv7l
F=/mnt/mmc/ffmpeg
$B killall -9 demo_audio 2>/dev/null; $B sleep 1
$B rm -f /tmp/af 2>/dev/null; $B mkfifo /tmp/af 2>/dev/null
/mnt/mmc/demo_audio 14 2>/dev/null > /tmp/af &
$B sleep 1
exec $F -hide_banner -loglevel error -use_wallclock_as_timestamps 1 -analyzeduration 0 -probesize 4096 -f alaw -ar 8000 -ac 1 -i /tmp/af -map 0:a -c:a copy -muxdelay 0 -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/cam