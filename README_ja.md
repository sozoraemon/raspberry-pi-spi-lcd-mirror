# Raspberry Pi SPI LCD Mirror

Raspberry Pi 5のデスクトップ画面を、3.5インチのMHS35 SPI液晶（480×320）にミラーリングするプログラムです。

**WaylandのDMA-BUFによる画面取得とC言語による画像処理を採用し、20FPSでの安定した画面表示を実現しています。**

ADS7846タッチパネルにも対応しており、画面の回転やタッチ位置の補正も可能です。

## 主な特徴

- **DMA-BUFによる画面取得**：Waylandの`zwlr_export_dmabuf_manager_v1`プロトコルを使用
- **C言語による高速処理**：画面の縮小、RGB565変換、フレームバッファーへの書き込みを実行
- **20FPSでの画面表示**：フレーム間隔を制御して安定した表示を実現
- **自動起動**：systemdによって起動時にミラーリングを開始
- **4方向の画面回転**：0°・90°・180°・270°に対応
- **タッチ操作**：ADS7846タッチパネルに対応し、9点キャリブレーションが可能

## 動作確認環境

- Raspberry Pi 5
- Raspberry Pi OS（Debian 13 / Trixie）
- MHS35 SPI液晶（480×320）
- ADS7846タッチパネル
- labwc（Wayland）
- ミラーリング元の画面：`NOOP-1`

### 動作性能

Raspberry Pi 5での実測結果です。

| 項目 | 測定結果 |
|---|---|
| 画面取得方式 | Wayland DMA-BUF |
| プログラミング言語 | C |
| ミラーリング元の解像度 | 960×640 |
| SPI液晶の解像度 | 480×320 |
| 画面表示 | 約20FPS |
| 平均CPU温度 | 約76.8℃ |
| CPU周波数制限 | なし |

CPU温度は、室温やRaspberry Piの負荷、設置環境などによって変化します。

## ミラーリングの仕組み

本プログラムは、Waylandの`zwlr_export_dmabuf_manager_v1`プロトコルを使用して、デスクトップ画面をDMA-BUF形式で取得します。

取得した画像はC言語で処理し、SPI液晶に表示します。

処理の流れは以下のとおりです。

```text
Raspberry Pi 5
     │
     ▼
Wayland（labwc）
     │
     ▼
DMA-BUFによる画面取得
     │
     ▼
C言語による画像処理
  ├─ 480×320に縮小
  └─ RGB565形式に変換
     │
     ▼
/dev/fb0
     │
     ▼
MHS35 SPI液晶
```

DMA-BUFを利用することで、画面取得時の不要なメモリコピーを削減できる可能性があります。

本環境では、DMA-BUF方式への変更によってCPU温度の低下を確認しています。

なお、取得した画像はCPUで読み取り、縮小とRGB565変換を行うため、完全なゼロコピー処理ではありません。

## インストール

ターミナルで以下を実行してください。

```bash
git clone https://github.com/sozoraemon/raspberry-pi-spi-lcd-mirror.git
cd raspberry-pi-spi-lcd-mirror
sudo bash install.sh
```

インストーラーは、必要なパッケージの導入、C言語プログラムのコンパイル、SPI液晶の設定、systemdサービスの登録を行います。

インストール完了後、Raspberry Piを再起動します。

```bash
sudo reboot
```

再起動すると、デスクトップ画面がSPI液晶にミラーリングされます。

### 動作確認

ミラーリングサービスの状態を確認します。

```bash
sudo systemctl status spi-mirror
```

FPSを確認する場合は、以下を実行してください。

```bash
sudo journalctl -u spi-mirror -f
```

正常に動作している場合、約10秒ごとにFPSが表示されます。

```text
FPS: 20.0
FPS: 20.0
FPS: 19.9
```

## 画面の回転

`spi-rotate`コマンドを使用すると、SPI液晶の画面を0°・90°・180°・270°の4方向に回転できます。

```bash
sudo spi-rotate 0
sudo spi-rotate 90
sudo spi-rotate 180
sudo spi-rotate 270
```

画面の回転方向に合わせて、解像度とタッチパネルの補正値も自動的に変更されます。

| 回転角度 | 解像度 |
|---|---|
| 0° | 320×480 |
| 90° | 480×320 |
| 180° | 320×480 |
| 270° | 480×320 |

初期設定は270°です。

コマンド実行後、以下の確認メッセージが表示されます。

```text
Reboot now? [Y/n]:
```

Enterキーを押すと再起動し、変更が反映されます。

4方向すべてで画面表示とタッチ操作の正常動作を確認しています。

## 画面の解像度変更

MHS35液晶の解像度は480×320ですが、Raspberry Piの画面は初期設定で1920×1080になっています。

この画面を小さな液晶に縮小して表示するため、そのままでは文字やアイコンが非常に小さくなってしまいます。

そこで、Raspberry Piの画面解像度を**960×640**に変更することをおすすめします。

液晶と同じ縦横比（3:2）になるため、画面が変形せず、文字やアイコンも見やすくなります。

以下のコマンドを実行すると、起動時に解像度が自動設定されます。

```bash
mkdir -p ~/.config/labwc
echo '( sleep 3; wlr-randr --output NOOP-1 --custom-mode 960x640 ) &' >> ~/.config/labwc/autostart
```

設定後、Raspberry Piを再起動してください。

```bash
sudo reboot
```

## タッチ位置の補正

画面をタッチした位置と実際に反応する位置がずれている場合は、以下のコマンドで9点キャリブレーションを実行してください。

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

画面に表示される9個の十字マークを順番にタッチします。

測定が完了すると、以下の確認メッセージが表示されます。

```text
Save calibration rule? [y/N]:
```

`y`を入力してEnterキーを押すと、補正値が保存されます。

保存後、Raspberry Piを再起動してください。

## 注意事項

- Raspberry Pi 5で動作確認しています。
- Raspberry Pi OS TrixieのWayland（labwc）環境を対象としています。
- Waylandソケットは`wayland-0`、ミラーリング元のディスプレイは`NOOP-1`を想定しています。
- DMA-BUFの取得には`zwlr_export_dmabuf_manager_v1`への対応が必要です。
- 現在のC言語版は、CPUから読み取り可能なリニア形式のDMA-BUFに対応しています。
- インストーラーは既存の設定ファイルをバックアップします。
- その他のRaspberry Piや液晶での動作は未検証です。

## 謝辞

本プロジェクトで使用しているMHS35用デバイスツリーオーバーレイ（`mhs35.dtbo`）は、以下のプロジェクトで公開されているものです。

**Robinbinu / pi5-mhs35-touchscreen**

https://github.com/Robinbinu/pi5-mhs35-touchscreen

Raspberry Pi 5でMHS35を動作させるための技術情報と成果物を公開してくださったRobinbinu氏に感謝いたします。

本プロジェクトでは、これを基にWaylandデスクトップのミラーリングやタッチ操作に対応する機能を追加しています。

元プロジェクトの著作権およびライセンス条件を尊重します。
