# Raspberry Pi SPI LCD Mirror

Raspberry Pi 5のデスクトップ画面を、3.5インチのMHS35 SPI液晶（480×320）に表示するプログラムです。

ADS7846タッチパネルにも対応しています。

## 動作確認環境

- Raspberry Pi 5
- Raspberry Pi OS（Debian 13 / Trixie）
- MHS35 SPI液晶（480×320）
- labwc（Wayland）

## インストール

ターミナルで以下を実行してください。

```bash
git clone https://github.com/sozoraemon/raspberry-pi-spi-lcd-mirror.git
cd raspberry-pi-spi-lcd-mirror
sudo bash install.sh
```

インストール完了後、Raspberry Piを再起動します。

```bash
sudo reboot
```

再起動すると、デスクトップ画面がSPI液晶にミラーリングされます。

## タッチ位置の補正

タッチ位置がずれる場合は、以下のコマンドで9点キャリブレーションを実行してください。

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

画面に表示される十字マークを順番にタッチします。

補正値を保存したら、Raspberry Piを再起動してください。

## 注意事項

- Raspberry Pi 5で動作確認しています。
- Waylandソケットは`wayland-0`、ミラーリング元のディスプレイは`NOOP-1`を想定しています。
- インストーラーは既存の設定ファイルをバックアップします。
- その他のRaspberry Piや液晶での動作は未検証です。

## 謝辞

本プロジェクトで使用しているMHS35用デバイスツリーオーバーレイ（mhs35.dtbo）は、以下のプロジェクトで公開されているものです。

**Robinbinu / pi5-mhs35-touchscreen**

https://github.com/Robinbinu/pi5-mhs35-touchscreen

Raspberry Pi 5でMHS35を動作させるための技術情報と成果物を公開してくださったRobinbinu氏に感謝いたします。

本プロジェクトでは、これを基にWaylandデスクトップのミラーリングやタッチ操作に対応する機能を追加しています。

元プロジェクトの著作権およびライセンス条件を尊重します。
