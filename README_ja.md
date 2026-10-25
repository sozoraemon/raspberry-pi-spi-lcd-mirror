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

そこで、Raspberry Piの画面解像度を**960×640**に変更することをおすすめします。液晶と同じ縦横比（3:2）になるため、画面が変形せず、文字やアイコンも見やすくなります。

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

タッチ位置がずれる場合は、以下のコマンドで9点キャリブレーションを実行してください。

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
