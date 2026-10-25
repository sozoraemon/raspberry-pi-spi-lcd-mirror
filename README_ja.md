# Raspberry Pi SPI LCD Mirror

Raspberry PiのWaylandデスクトップ画面を、3.5インチのMHS35 SPI液晶ディスプレイにミラーリングするプロジェクトです。ADS7846タッチパネルによる操作にも対応しています。

液晶への表示にはLinuxのフレームバッファ（`/dev/fb0`）を使用します。`grim`でWaylandデスクトップの画面を取得し、FFmpegでRGB565形式に変換して液晶に表示します。

また、systemdを使用することで、Raspberry Piの起動時にミラーリングを自動開始できます。

> **動作確認済み環境**
> - Raspberry Pi 5
> - Raspberry Pi OS（Debian 13 / Trixie）
> - labwc（Wayland）
> - MHS35 3.5インチSPI液晶（480×320）
> - ADS7846タッチパネル
>
> その他のRaspberry Piや液晶ディスプレイでの動作は未検証です。

## ファイル構成

| ファイル | 内容 |
| --- | --- |
| `mhs35.dtbo` | MHS35液晶とタッチパネル用のデバイスツリーオーバーレイ |
| `spi-mirror.sh` | Wayland画面を取得して`/dev/fb0`に転送するスクリプト |
| `spi-mirror.service` | systemdによるミラーリングの自動起動設定 |
| `mhs35_calibrate.py` | タッチ位置を補正する9点キャリブレーションプログラム |

## 1. 必要なパッケージのインストール

Raspberry Piのターミナルを開き、以下のコマンドを実行します。

```bash
sudo apt update
sudo apt install -y grim ffmpeg evtest libinput-tools python3-evdev python3-pil python3-numpy
```

ミラーリングスクリプトは、以下の環境を前提としています。

- ユーザー名：`pi`
- ユーザーID（UID）：`1000`
- Waylandソケット：`wayland-0`

ユーザー名やUID、Waylandソケットが異なる場合は、サービスを有効化する前に`spi-mirror.sh`を修正してください。

## 2. SPI液晶の有効化

### デバイスツリーオーバーレイのコピー

リポジトリに含まれる`mhs35.dtbo`を、Raspberry Piのオーバーレイ用ディレクトリにコピーします。

```bash
sudo cp mhs35.dtbo /boot/firmware/overlays/
```

### config.txtの編集

以下のコマンドで設定ファイルを開きます。

```bash
sudo nano /boot/firmware/config.txt
```

次の設定を追加します。

```ini
dtoverlay=vc4-kms-v3d
max_framebuffers=2
dtoverlay=nospi10
dtparam=spi=on
dtoverlay=mhs35:rotate=270,speed=24000000
```

すでに同じ設定が存在する場合は、重複して追加しないでください。

### 画面左上の点滅カーソルを非表示にする

フレームバッファのコンソールカーソルが液晶に表示される場合があります。

これを防ぐため、以下のファイルを編集します。

```bash
sudo nano /boot/firmware/cmdline.txt
```

既存の1行の末尾に、次のパラメータを追加します。

```text
vt.global_cursor_default=0
```

**注意：** `cmdline.txt`は1行で記述する必要があります。改行を追加したり、既存のパラメータを削除したりしないでください。

### 再起動

```bash
sudo reboot
```

再起動後、フレームバッファが作成されていることを確認します。

```bash
ls -l /dev/fb0
```

**重要：** `/dev/fb0`がMHS35液晶に対応し、解像度480×320、16bit RGB565形式になっている必要があります。

本プロジェクトのスクリプトは、この構成を前提としています。

## 3. ミラーリングのインストールと自動起動

ダウンロードしたリポジトリのファイルが保存されているディレクトリで、以下を実行します。

```bash
sudo install -m 755 spi-mirror.sh /usr/local/bin/spi-mirror.sh
sudo install -m 644 spi-mirror.service /etc/systemd/system/spi-mirror.service

sudo systemctl daemon-reload
sudo systemctl enable --now spi-mirror.service
```

これで、ミラーリングサービスが登録され、自動起動が有効になります。

### 動作確認

```bash
systemctl status spi-mirror.service
```

サービスが正常に動作していれば、Raspberry Piのデスクトップ画面がSPI液晶に表示されます。

### 画面解像度について

現在のスクリプトは、Waylandデスクトップ全体を取得し、**480×320ピクセルに縮小して表示**します。

動作確認時の仮想ディスプレイは、以下の設定でした。

- ディスプレイ名：`NOOP-1`
- 解像度：1280×720

その他の解像度でも動作する可能性がありますが、元の画面と液晶の縦横比が異なる場合、映像が引き伸ばされて表示されます。

## 4. labwcでタッチパネルを設定する

ADS7846タッチパネルの入力を、ミラーリング元のWaylandディスプレイに割り当てます。

### ディスプレイとタッチパネルの確認

```bash
wlr-randr
libinput list-devices
```

動作確認環境では、仮想ディスプレイ名は`NOOP-1`でした。

### labwcの設定

設定ディレクトリを作成し、`rc.xml`を編集します。

```bash
mkdir -p ~/.config/labwc
nano ~/.config/labwc/rc.xml
```

既存の`<openbox_config>`要素の内側に、`<touch>`の設定を追加します。

最小構成の例は以下のとおりです。

```xml
<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <touch deviceName="ADS7846 Touchscreen" mapToOutput="NOOP-1" mouseEmulation="yes"/>
</openbox_config>
```

すでにほかの設定がある場合は、それらを削除せずに`<touch>`要素だけを追加してください。

設定を再読み込みします。

```bash
labwc --reconfigure
```

`wlr-randr`で確認したディスプレイ名が`NOOP-1`ではない場合は、`mapToOutput`の値を変更してください。

## 5. タッチ位置の補正

タッチパネルは、認識されていても実際に触れた位置とクリック位置が一致しない場合があります。

そこで、タッチ座標を補正する設定を追加します。

### 動作確認済みの補正値

以下の補正値は、実際のMHS35液晶で9点キャリブレーションを実施して取得したものです。

**まずはこの補正値を使用し、タッチ位置が合わない場合だけ再キャリブレーションしてください。**

以下のコマンドを実行します。

```bash
sudo tee /etc/udev/rules.d/99-ads7846-calibration.rules > /dev/null <<'EOF_RULE'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", ENV{LIBINPUT_CALIBRATION_MATRIX}="0.000462 1.092691 -0.053591 -1.112591 0.000905 1.062629"
EOF_RULE

sudo reboot
```

### タッチ位置の確認

再起動後、画面の以下の位置をタッチして確認します。

- 左上・右上
- 中央
- 左下・右下

実際に触れた位置で正しくクリックできれば、設定完了です。

**タッチ位置が正常であれば、次の9点キャリブレーションは不要です。**

タッチパネルには個体差があるため、位置が合わない場合は次の手順で補正してください。

## 6. 9点キャリブレーション（必要な場合のみ）

標準の補正値でタッチ位置が合わない場合は、Pythonプログラムを使用して補正値を自動計算できます。

### プログラムのインストール

```bash
sudo install -m 755 mhs35_calibrate.py /usr/local/bin/mhs35_calibrate.py
```

### キャリブレーションの実行

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

### プログラムの動作

1. 実行中の`spi-mirror.service`を一時停止します。
2. SPI液晶に9個の測定用ターゲットを順番に表示します。
3. 各ターゲットをタッチすると、ADS7846の生座標を取得します。
4. 9点の測定結果から、最小二乗法によって補正行列を計算します。
5. 平均誤差と最大誤差を表示します。
6. 保存を確認した後、既存の設定をバックアップして新しい補正値を保存します。
7. 終了時にミラーリングサービスを再開します。

### 測定方法

画面に表示される十字マークの中心を、順番にタッチしてください。

できるだけ正確に測定するため、先端の細いタッチペンの使用をおすすめします。

十字の中心を少し長めに押してから離すと、次の測定位置に進みます。

9点の測定が終了すると、次の確認が表示されます。

```text
Save calibration rule? [y/N]:
```

補正値を保存する場合は、`y`を入力してください。

保存後、Raspberry Piを再起動します。

```bash
sudo reboot
```

### 注意事項

現在のキャリブレーションプログラムは、以下のデバイスを使用する設定です。

| デバイス | パス |
| --- | --- |
| ADS7846タッチパネル | `/dev/input/event5` |
| MHS35液晶 | `/dev/fb0` |

`/dev/input/event5`の番号は、起動環境によって変わる場合があります。

タッチパネルが認識されない場合は、以下のコマンドでデバイス番号を確認してください。

```bash
libinput list-devices
```

必要に応じて、`mhs35_calibrate.py`の先頭付近にある`DEVICE`の設定を変更してください。

また、プログラムは480×320ピクセルの液晶を前提としています。

## トラブルシューティング

### 液晶に何も表示されない

まず、ミラーリングサービスの状態を確認してください。

```bash
systemctl status spi-mirror.service
```

続いて、`/dev/fb0`がMHS35液晶に対応していること、Waylandセッションが起動していることを確認します。

また、現在のスクリプトは以下の設定を使用しています。

- ユーザー名：`pi`
- UID：`1000`
- Waylandソケット：`wayland-0`

環境が異なる場合は、`spi-mirror.sh`を修正してください。

### タッチ位置がずれる

まず、labwcの`mapToOutput`がミラーリング元のディスプレイを指しているか確認してください。

続いて、手順5の補正値を適用します。

それでも位置が合わない場合は、手順6の9点キャリブレーションを実行してください。

### Pythonでevdevのエラーが発生する

以下のエラーが表示される場合があります。

```text
ModuleNotFoundError: No module named 'evdev'
```

この場合は、必要なライブラリをインストールしてください。

```bash
sudo apt install -y python3-evdev
```

プログラムは次のように実行します。

```bash
sudo /usr/bin/python3 /usr/local/bin/mhs35_calibrate.py
```

### 画面が横方向や縦方向に引き伸ばされる

ミラーリングスクリプトは、取得したデスクトップ画面を480×320ピクセルに変換します。

元の画面と液晶の縦横比が異なる場合、映像が引き伸ばされます。

液晶と同じ**3:2の縦横比**を持つ解像度を使用すると、映像の歪みを防げます。

ただし、選択する解像度がWaylandコンポジターで使用できる必要があります。

## デバイスツリーオーバーレイの出典とライセンス

本プロジェクトで使用している`mhs35.dtbo`は、以下のプロジェクトに由来します。

[Robinbinu/pi5-mhs35-touchscreen](https://github.com/Robinbinu/pi5-mhs35-touchscreen)

再配布する場合は、元プロジェクトのライセンス条件を確認し、必要な著作権表示やライセンス表記を保持してください。

また、本リポジトリで独自に作成したスクリプトのライセンスは、別途設定する必要があります。

元プロジェクト由来のファイルを含めても、その著作権が本リポジトリに移転するわけではありません。

## 制限事項

- 動作確認済みのRaspberry Piは、Raspberry Pi 5のみです。
- SPI液晶は既存のWayland画面をミラーリングする方式であり、独立したWaylandディスプレイとして認識されるわけではありません。
- 現在のミラーリングスクリプトは、画面の取得と画像変換を繰り返す方式のため、CPU負荷が高くなる場合があります。
- 動画などの滑らかな再生には適さない場合があります。
- タッチ座標の補正にはアフィン変換を使用しているため、抵抗膜タッチパネル特有の非線形な歪みがある場合は、わずかな位置誤差が残る可能性があります。
