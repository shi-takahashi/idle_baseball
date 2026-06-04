#!/usr/bin/env bash
# 眼力ベースボール アプリアイコン生成スクリプト。
# ImageMagick のネイティブ描画(MVG)で 1024x1024 のマスター画像を作る。
# （IM 内蔵 SVG レンダラは stroke/line が不安定なため SVG ではなく -draw で描く）
#
# 使い方: bash assets/icon/build_icon.sh
# 出力:
#   assets/icon/app_icon.png             … 通常アイコン（背景込み・正方形フルブリード）
#   assets/icon/app_icon_foreground.png  … Android アダプティブ用フォアグラウンド
#                                          （背景透過・セーフゾーンに収まるよう縮小）
# どちらも flutter_launcher_icons の入力にする。
set -euo pipefail
cd "$(dirname "$0")"

BG='#0f254e'      # 背景 濃紺
BALL='#f6f2e7'    # ボール クリーム白
SEAM='#d23b2e'    # 縫い目 赤

# モチーフ（背景透過）: シンプルな野球ボール（クリーム白 + 赤い縫い目 + ステッチ）。
# 実物の「ホースシュー」状の見えに寄せ、2本の縫い目を中央寄りで同方向に湾曲させる。
magick -size 1024x1024 xc:none \
  -fill "${BALL}" -stroke none -draw "circle 512,512 512,182" \
  -fill none -stroke "${SEAM}" -strokewidth 20 \
    -draw "stroke-linecap round path 'M392,212 C300,360 300,664 392,812'" \
    -draw "stroke-linecap round path 'M632,212 C724,360 724,664 632,812'" \
  -strokewidth 12 \
    -draw "stroke-linecap round line 360,250 408,268" -draw "stroke-linecap round line 326,372 376,360" \
    -draw "stroke-linecap round line 316,500 366,500"  -draw "stroke-linecap round line 326,628 376,640" \
    -draw "stroke-linecap round line 360,750 408,732" \
    -draw "stroke-linecap round line 616,268 664,250" -draw "stroke-linecap round line 648,360 698,372" \
    -draw "stroke-linecap round line 658,500 708,500"  -draw "stroke-linecap round line 648,640 698,628" \
    -draw "stroke-linecap round line 616,732 664,750" \
  motif.png

# 通常アイコン: モチーフを濃紺背景に重ねる
magick -size 1024x1024 "xc:${BG}" motif.png -composite app_icon.png

# アダプティブ・フォアグラウンド: アダプティブ側で 16% inset(=実効68%)がかかり
# ボールが小さくなりすぎるので、余白を詰めてボールがフレームの ~88% を占める形に。
# inset 後でボール径 ~60%・半径 ~0.30 となりセーフゾーン(半径0.33)に収まる。
magick motif.png -trim +repage -resize 900x900 -background none -gravity center -extent 1024x1024 app_icon_foreground.png

rm -f motif.png
echo "wrote app_icon.png and app_icon_foreground.png"
