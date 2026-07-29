#!/bin/sh
B=/mnt/mmc/busybox-armv7l
F=/mnt/mmc/ffmpeg
S=${1:-11}
$B killall -9 demo_dump 2>/dev/null; $B sleep 1
$B rm -f /tmp/vf 2>/dev/null; $B mkfifo /tmp/vf 2>/dev/null
/mnt/mmc/demo_dump "$S" 2>/dev/null > /tmp/vf &
$B sleep 1
exec $F -hide_banner -loglevel error -use_wallclock_as_timestamps 1 -analyzeduration 300000 -probesize 120000 -f hevc -i /tmp/vf -map 0:v -c:v copy -muxdelay 0 -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/cam