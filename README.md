# miSafes D304 — RTSP 化キット

miSafes **D304**（InfoTM iMAPx15 SoC）を、microSD を挿して電源ONするだけで
**ハードウェア H.265 映像＋マイク音声を RTSP 配信する防犯カメラ**にするキットです。
miSafes のスマホアプリ**とクラウドがサービス終了**して使えなくなった端末を蘇らせます。

汎用の防犯カメラアプリ（TinyCam / IP Cam Viewer / Frigate / Blue Iris / Synology）や
VLC・ffplay から視聴できます：

```
rtsp://<カメラIP>:8554/cam     # HW H.265 720p 映像 + G.711 PCMA 音声
```

映像・音声とも**無変換（copy）**なので単核 CPU でも軽く、常時配信されます。
同梱の **go2rtc** が RTSP/WebRTC/HTTP と API(`:1984`) で再配信します。

---

## ⚠️ 独自バイナリは同梱していません（初回起動でカメラ自身から生成）

`demo_dump` / `demo_audio` / `demo_se0` は、カメラのファーム
**`/opt/ipnc/demo`（miSafes/InfoTM のコード）を数十バイト改変したもの**です。
これらはリポジトリに含めず、初回起動時に **`bootstrap_demo.sh`** が生成します：

1. あなたのカメラの `/opt/ipnc/demo` を読む（md5 を検証）
2. 本キットの RTSP 用バイトパッチを `dd` で適用
3. 各出力の md5 を検証して `demo_dump` / `demo_audio` / `demo_se0` を書き出す

＝関与する miSafes コードは「あなたのカメラに元からある1本」だけ。リポジトリが持つのは
小さなバイト差分のみです。冪等（生成済みならスキップ）。

---

## 使い方

1. microSD を **FAT32** でフォーマット。
2. **`sdcard/` の中身を SD のルートに全部コピー**（テキストは LF 改行済み）。
3. **WiFi 設定**：`secrets.conf.example` を `secrets.conf` にコピーし、SSID/PSK を記入
   （このファイルは gitignore 済み＝公開されません）。
4. *(任意)* **SSH 公開鍵**：`authorized_keys.example` を `authorized_keys` にコピーし
   自分の公開鍵を貼る。
5. SD を挿して電源ON。約30〜40秒で WiFi 接続し `rtsp://<IP>:8554/cam` を配信開始。
   VLC では **TCP** トランスポートで開く。

> SD を抜く前に**必ずカメラの電源を切る**（不正な取り外しで FAT が壊れます）。
> ハード電源の連続抜き差しは避ける（D304 は工場リセットされ `/mnt/config` の登録
> ファイルが消えます。キットが再生成しますが手間です）。

---

## 視聴 URL（go2rtc が同時に複数プロトコルで配信）

| 用途 | URL |
|---|---|
| **RTSP**（防犯カメラアプリ/VLC/NVR） | `rtsp://<IP>:8554/cam` |
| ブラウザ確認ページ | `http://<IP>:1984/` → `cam` |
| MP4 (HTTP) | `http://<IP>:1984/api/stream.mp4?src=cam` |

---

## 仕組み

```
avserver_q3.bin (ISP + HW H.265 + マイク G711) ──▶ 共有メモリ(SHM)リング
   ▲ demo_se0 が IPC(cmd 0xcf/mtype2)でストリーム0(720p)を有効化
   │
   ├─ demo_dump 11  (SHM から H.265 Annex-B) ─▶ ffmpeg -c:v copy ─┐
   └─ demo_audio 14 (SHM から G711 a-law)     ─▶ ffmpeg -c:a copy ─┤─▶ go2rtc :8554/cam
                                                                    │   (2 producer を統合)
```

- **映像用 ffmpeg と音声用 ffmpeg を分離**し、go2rtc 側で1本の `cam` に統合します。
  1本の ffmpeg で A/V を mux すると、遅い音声 FIFO の読み取りで映像 FIFO が詰まり
  **3fps に激落ち**するため。分離で約9fps。
- **死んだクラウド系デーモンを止めるウォッチドッグ**を常駐。`p2ptutk`（P2Pトンネル）や
  `qiwocloud1` への `setVideoFile` アップロード(curl)、`app_qiwo`、`bsa_server` が
  単核を100%飽和させて HW エンコーダを餓死させていた（kill で idle 0%→66%）。

---

## フレームレートについて

~9fps は **CPU ではなくエンコーダの上限**です。CPU が 66% 空いていても 720p H.265 は
~10fps（avserver のストリーム0レート）で頭打ちで、CPU を空けても上がりません。
さらに上げるには avserver のストリーム設定変更（本キットの範囲外）が必要か、
あるいは単に**明るい環境**が要る可能性があります（防犯センサーは暗所で fps を落とす）。

---

## 同梱ファイル

| ファイル | 役割 | 配布 |
|---|---|---|
| `testlauncher.sh` | ブート＆設定（`APP_SELECT=4`＝RTSP）。WiFi/SSH/cloud-kill/bootstrap 呼び出し。 | 本キット |
| `bootstrap_demo.sh` | 初回に `/opt/ipnc/demo` から `demo_*` を生成（上記参照）。 | 本キット |
| `pub_video.sh` / `pub_audio.sh` | 映像専用 / 音声専用パブリッシャ（`-c copy`）。 | 本キット |
| `go2rtc.yaml` | go2rtc 設定（`cam` = 空定義＝publish 受け口）。 | 本キット |
| `secrets.conf.example` | WiFi 認証情報のテンプレ（実ファイルは gitignore）。 | 本キット |
| `authorized_keys.example` | SSH 公開鍵のテンプレ（実ファイルは gitignore）。 | 本キット |
| `busybox-armv7l` | BusyBox（静的 ARMv7）。 | OSS(GPLv2) |
| `dropbear` | SSH サーバ（静的・ソフトフロート・公開鍵のみ）。 | OSS |
| `ffmpeg` | 静的 ARM ffmpeg（`-c copy` 再多重化）。 | OSS(GPL/LGPL) |
| `go2rtc` | RTSP/WebRTC/HTTP サーバ（Go 静的）。 | OSS(MIT) |
| `demo_dump` / `demo_audio` / `demo_se0` | **同梱せず**。初回起動で生成。 | 端末由来 |

OSS 各コンポーネントのソースは各上流プロジェクトから入手できます。

---

## 注意・制限

- **同一機種専用**（miSafes D304 / InfoTM iMAPx15）。物理アドレス・IPC・オフセットは機種依存。
  `bootstrap_demo.sh` は `/opt/ipnc/demo` の md5 が想定と違えば安全に中止します。
- クライアントは **H.265(HEVC) 対応**が必要（TinyCam/VLC/Edge/iOS 等。Chrome/Firefox 素の再生は不可）。
- 音声は **G.711 PCMA（RTP payload 8）**をそのまま配信（変換なし）。
- 複数エンコーダストリームの反復 ON/OFF は避ける（ISP がウェッジし物理電源再投入が必要）。
- WiFi 未接続時は配信できません（起動ログは SD の `wifi_result.txt`）。

---

## クレジット

D304 の登録フロー・HW エンコーダ解析は PIGYO 氏の Qiita 記事を参考にしています：
- https://qiita.com/PIGYO/items/b86547f67e534db4d560
- https://qiita.com/PIGYO/items/12632147f73ddf12965c

## 免責

本キットは**現状有姿（AS IS）・無保証**で提供されます。動作、品質、正確性、安全性、特定用途への適合性、継続的な利用可能性について、**一切の保証を行いません**。

本キットは**自己の責任において所有する端末でのみ使用してください**。本キットは端末に元から存在する独自ファームウェアと連携しますが、**それ自体は同梱していません**。

本キットには**AIを用いて作成・生成されたコードや設定が含まれる場合があります**。そのため、**正常に動作する保証はなく**、不具合、予期しない動作、データ破損、端末の故障、起動不能（ブリック）、通信障害、セキュリティ上の問題、その他あらゆる不利益が発生する可能性があります。

本キットの使用または使用不能により生じた**直接損害、間接損害、特別損害、付随的損害、逸失利益、データ消失、営業損失、第三者からの請求その他一切の損害について、作者は一切の責任を負いません**。本キットを使用した時点で、利用者は**これらのリスクを理解し、自らの責任において利用することに同意したものとみなします**。