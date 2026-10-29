# 『ファミコンで学ぶアセンブラ入門』サンプルコード

書籍『ファミコンで学ぶアセンブラ入門』（トゲトゲ団）のサンプルコードです。
6502 アセンブリで、ファミコンの画面に白い四角を出すところから始めて、1 本の縦シューティングゲームを完成させるまでを章ごとに収録しています。

## 収録しているサンプル

| フォルダー | ビルドするファイル | 対応する章 | 内容 |
|---|---|---|---|
| `01_show_sprite/` | `01_show_sprite.asm` | 第 1 章 | 画面にスプライトを 1 個表示する（1 ファイルで完結） |
| `02_show_sprite/` | `02_show_sprite.asm` | 第 2・3 章 | 01 をサブルーチンとファイル分割で整理する |
| `03_move_sprite/` | `03_move_sprite.asm` | 第 4 章 | 十字ボタンでスプライトを動かす（最小の実装） |
| `04_read_pads/` | `04_read_pads.asm` | 第 4 章 | 1P / 2P コントローラーのベタ入力とワンショット入力 |
| `05_fixed_speed/` | `05_fixed_speed.asm` | 第 5・6 章 | 固定小数で速度を細かく調整する |
| `06_shoot_01/` | `06_shoot_01.asm` | 第 7 章 | 16 × 16 の自機を表示して操作する |
| `07_shoot_02/` | `07_shoot_02.asm` | 第 8 章 | 自機から弾を発射する |
| `08_shoot_03/` | `08_shoot_03.asm` | 第 9 章 | 敵をサイン波で動かす |
| `09_shoot_04/` | `09_shoot_04.asm` | 第 10 章 | 当たり判定を入れる |
| `10_shoot_05/` | `10_shoot_05.asm` | 第 11 章 | BG にスコアを表示する |
| `11_complete_game/` | `11_complete_game.asm` | 第 12 章 | タイトル・残機・ゲームオーバーを入れて完成させる |
| `lib/` | （単体ではビルドしない） | 第 2 章〜 | 02 以降のサンプルが共通で読み込むファイル |

`*_data.asm` や `*_vars.inc` は、メインのファイルから `.include` で読み込まれる部品です。ビルドするのは、上の表の「ビルドするファイル」だけです。

`lib/` の中身は次のとおりです。

| ファイル | 内容 |
|---|---|
| `ines.inc` | iNES ヘッダー（マッパー 0 / NROM） |
| `fc.inc` | PPU・APU・コントローラーの I/O レジスターとビット定数 |
| `fc_init.asm` | 起動直後の初期化（PPU の安定待ち、RAM のクリア） |
| `pad_vars.inc` | コントローラー入力用のゼロページ変数 |
| `macros.inc` | 16 bit 加減算のマクロ（ADD16 / SUB16） |

## 必要なもの

- **asm6f**（アセンブラ）: `.asm` から `.nes`（ROM イメージ）を作ります。
- **Mesen2**（エミュレーター）: `.nes` を PC 上で動かします。デバッガーやメモリビューアも使います。
- **Visual Studio Code**（任意）: 好きなテキストエディターで構いません。VS Code 用のタスク設定を `.vscode/tasks.json` に入れてあります。

macOS / Windows / Linux のどれでも動きます。

## 導入手順

### asm6f

配布元: <https://github.com/freem/asm6f>

- **Windows**: [Releases](https://github.com/freem/asm6f/releases) から最新版をダウンロードし、中の `asm6f.exe` を PATH の通ったフォルダーに置きます。
- **macOS / Linux**: ソースからビルドします。C コンパイラーと make が必要です（macOS では `xcode-select --install` で入ります）。

  ```sh
  git clone https://github.com/freem/asm6f.git
  cd asm6f
  make
  # できた asm6f を PATH の通ったフォルダーへコピーする（例: ~/.local/bin）
  cp asm6f ~/.local/bin/
  ```

インストールできたら、ターミナルで `asm6f` と打って使い方（`Usage: asm6f ...`）が表示されることを確かめてください。

### Mesen2

配布元: <https://www.mesen.ca/>

公式サイトから、お使いの OS 用の zip をダウンロードして展開します。

- **Windows**: Windows 10 以降。展開した `Mesen.exe` を起動します。
- **macOS**: Apple silicon 版と Intel 版があります。SDL2 が必要です（Homebrew なら `brew install sdl2`）。
- **Linux**: SDL2 が必要です（例: Debian / Ubuntu なら `sudo apt install libsdl2-2.0-0`）。

## ビルドと実行

サンプルのフォルダーに移動してから asm6f を実行します。02 以降のサンプルは `../lib/` を読み込むので、必ずそのサンプルのフォルダーの中で実行してください。

```sh
cd 01_show_sprite
asm6f 01_show_sprite.asm 01_show_sprite.nes
```

できた `.nes` を Mesen2 で開きます。Mesen2 の画面にファイルをドラッグ＆ドロップするか、メニューの `File` → `Open` から開いてください。

ほかのサンプルも同じ手順です。たとえば完成版のゲームは次のとおりです。

```sh
cd 11_complete_game
asm6f 11_complete_game.asm 11_complete_game.nes
```

### 操作方法（完成版）

| ボタン | 動作 |
|---|---|
| 十字ボタン | 自機を移動 |
| A | 弾を発射 |
| START | ゲーム開始、ゲームオーバーからタイトルへ戻る |

Mesen2 でのキーボードの割り当ては、`Settings` → `Input` で確認・変更できます。

## VS Code で使う場合

このフォルダーを VS Code で開くと、`.vscode/tasks.json` のタスクが使えます。

1. ビルドしたいサンプルの**メインのファイル**（上の表の「ビルドするファイル」）を開きます。
2. コマンドパレットから `Tasks: Run Task` を選び、次のどれかを実行します。
   - `asm6f: ビルド` — 開いているファイルをビルドして `.nes` を作ります（`Ctrl+Shift+B` / `Cmd+Shift+B` でも実行できます）。
   - `Mesen2: 起動` — 同じ名前の `.nes` を Mesen2 で開きます。
   - `ビルドして起動` — 上の 2 つを続けて実行します。

`Mesen2: 起動` は、Windows / Linux では `Mesen` が PATH に入っていること、macOS では `Mesen.app` が「アプリケーション」フォルダーにあることを前提にしています。環境に合わせて `tasks.json` を書き換えてください。

## 書籍との関係

- コードの解説は書籍の本文にあります。本文に載せているコードの抜粋は、このリポジトリのファイルと同じ内容です。
- ビルドしてできる `.nes` は、このリポジトリには含めていません。各自でビルドしてください。

## ライセンス

[MIT License](LICENSE) です。改造や再配布は自由に行えます。その際は著作権表示とライセンス文を残してください。

「ファミリーコンピュータ」「ファミコン」は任天堂株式会社の登録商標です。このリポジトリは任天堂株式会社とは関係ありません。
