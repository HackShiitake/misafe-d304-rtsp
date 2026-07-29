# Third Party Software Licenses

本キットには、以下のオープンソースソフトウェアが含まれています。

各ソフトウェアは、それぞれのライセンス条件に従って配布しています。
本キットのライセンス（Unlicense）は、以下の第三者ソフトウェアには適用されません。

---

## BusyBox

**ファイル**
```
busybox-armv7l
```

**用途**
```
静的 ARMv7 BusyBox
```

**配布元**
```
https://busybox.net/
```

**ライセンス**
```
GNU General Public License Version 2 (GPLv2)
```

**ライセンス情報**
```
https://busybox.net/license.html
```

**注意事項**

BusyBox は GPLv2 に基づいて配布されています。

本キットでは BusyBox のバイナリを含めて配布しています。
対応するソースコードは、上記公式サイトから入手できます。

BusyBox 自体の著作権およびライセンスは、元の権利者に帰属します。

---

## Dropbear SSH

**ファイル**
```
dropbear
```

**用途**
```
軽量 SSH サーバ
（静的ビルド・ソフトフロート・公開鍵認証用）
```

**配布元**
```
https://matt.ucc.asn.au/dropbear/dropbear.html
```

**ライセンス**
```
MIT/X11 License
```

**ライセンス情報**
```
https://matt.ucc.asn.au/dropbear/dropbear.html
```

**注意事項**

Dropbear は MIT/X11 License に基づいて配布されています。

著作権表示およびライセンス表示を保持しています。
Dropbear 自体の著作権は開発者に帰属します。

---

## FFmpeg

**ファイル**
```
ffmpeg
```

**用途**
```
静的 ARM FFmpeg
（-c copy による再多重化）
```

**配布元**
```
https://ffmpeg.org/
```

**ライセンス**
```
GNU General Public License (GPL)
または
GNU Lesser General Public License (LGPL)
```

**ライセンス情報**
```
https://ffmpeg.org/legal.html
```

**注意事項**

FFmpeg はビルド時の設定により GPL または LGPL の条件が適用されます。

本キットで使用する FFmpeg バイナリは、映像・音声ストリームの
コピーおよび再多重化用途で使用しています。

FFmpeg 本体の著作権およびライセンスは FFmpeg 開発者に帰属します。

---

## go2rtc

**ファイル**
```
go2rtc
```

**用途**
```
RTSP / WebRTC / HTTP ストリームサーバ
```

**配布元**
```
https://github.com/AlexxIT/go2rtc
```

**ライセンス**
```
MIT License
```

**ライセンス情報**
```
https://github.com/AlexxIT/go2rtc/blob/master/LICENSE
```

**注意事項**

go2rtc は MIT License に基づいて配布されています。

著作権表示およびライセンス表示を保持しています。
go2rtc 自体の著作権は開発者に帰属します。

---

# Summary

| Software | License | Source |
|---|---|---|
| BusyBox | GPLv2 | https://busybox.net/ |
| Dropbear | MIT/X11 License | https://matt.ucc.asn.au/dropbear/dropbear.html |
| FFmpeg | GPL/LGPL | https://ffmpeg.org/ |
| go2rtc | MIT License | https://github.com/AlexxIT/go2rtc |
