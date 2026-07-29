<#
  deploy.ps1 -- miSafes D304 RTSP 化キットを microSD に書き込む
  ----------------------------------------------------------------------------
  sdcard\ の中身(LF済み)を SD ルートへコピーし、WiFi 認証情報を secrets.conf に書く。
  管理者権限・追加インストール不要。

  使い方:
    .\deploy.ps1 -Dest F:\
    .\deploy.ps1 -Dest F:\ -Ssid "MyWiFi" -Psk "pass1234"

    -Dest        : microSD のルート (例 F:\) か任意フォルダ。
    -Ssid / -Psk : WiFi 認証情報。指定すると Dest\secrets.conf に書き込む。
                   省略時、Dest に secrets.conf が無ければ雛形をコピーして警告。

  ※ 独自バイナリ(demo_dump/demo_audio/demo_se0)は同梱されず、初回起動時に
     カメラの /opt/ipnc/demo から bootstrap_demo.sh が自動生成します。
  ----------------------------------------------------------------------------
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Dest,
  [string]$Ssid='',
  [string]$Psk=''
)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $root 'sdcard'
if(-not (Test-Path $src)){ throw "sdcard フォルダが見つかりません: $src" }
if(-not (Test-Path $Dest)){ throw "Dest が見つかりません: $Dest" }
$Dest = (Resolve-Path $Dest).Path
$enc  = New-Object System.Text.UTF8Encoding($false)

Write-Host "==> コピー: $src\* -> $Dest"
Copy-Item (Join-Path $src '*') $Dest -Recurse -Force

# --- テキストは LF 維持 ---
foreach($f in 'testlauncher.sh','bootstrap_demo.sh','pub_video.sh','pub_audio.sh','go2rtc.yaml','secrets.conf'){
  $p = Join-Path $Dest $f
  if(Test-Path $p){ [IO.File]::WriteAllText($p, ([IO.File]::ReadAllText($p) -replace "`r`n","`n" -replace "`r","`n"), $enc) }
}

# --- WiFi 認証情報 -> secrets.conf ---
$scPath = Join-Path $Dest 'secrets.conf'
if($Ssid -ne '' -or $Psk -ne ''){
  [IO.File]::WriteAllText($scPath, ("SSID=`"$Ssid`"`nPSK=`"$Psk`"`n"), $enc)
  Write-Host "==> secrets.conf を書き込みました (SSID=$Ssid)"
}
elseif(-not (Test-Path $scPath)){
  $ex = Join-Path $Dest 'secrets.conf.example'
  if(Test-Path $ex){ Copy-Item $ex $scPath -Force }
  Write-Warning "secrets.conf が未設定です。$scPath を編集して SSID/PSK を入れてください（未設定だと WiFi に繋がりません）。"
}

$ssidNow = if(Test-Path $scPath){ [regex]::Match([IO.File]::ReadAllText($scPath),'(?m)^SSID="(.*)"').Groups[1].Value } else { '(未設定)' }
Write-Host ""
Write-Host "==================== 完了 ===================="
Write-Host "  モード     = RTSP (APP_SELECT=4)"
Write-Host ("  WiFi SSID  = {0}" -f $ssidNow)
Write-Host ("  配置先     = {0}" -f $Dest)
Write-Host "=============================================="
Write-Host "  ※ SSH 公開鍵を使うなら authorized_keys.example -> authorized_keys に自分の鍵を"
Write-Host "  ※ demo_* は初回起動時に自動生成 (bootstrap_demo.sh)"
Write-Host "  microSD をカメラに挿し電源ON -> 約30-40秒で配信開始"
Write-Host "  視聴: rtsp://<カメラIP>:8554/cam   (VLC は TCP / TinyCam 等)"
