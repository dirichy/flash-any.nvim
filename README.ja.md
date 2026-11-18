# ⚡ flash-any.nvim

[English](README.md) · [简体中文](README.zh-CN.md)

> **移行中のため、現在は不安定です。** `main` は C のマッチングコアと新しい設定 API を使います。
> 以前の版については [master の英語 README](https://github.com/dirichy/flash-any.nvim/blob/master/README.old.md) を参照してください。

ラテン文字の変種、中国語の拼音、日本語のローマ字、アイコン名などで検索してジャンプします。
[flash.nvim](https://github.com/folke/flash.nvim) を使い、実行時のマッチングはすべて C で処理します。

![共通先頭コードの f 連続移動・s・r・画面外の混在検索](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[高画質 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [検証結果](https://github.com/dirichy/flash-any.nvim/releases/download/demos/verification.json)

デモでは複数 source に共通する先頭コードで `fz` と `f` の連続移動、`s` のラベル移動、
`yr` のリモートコピー、画面外までの混在検索を紹介します。入力を続けると似た候補を順に飛ばします。

## インストールと設定

Neovim **0.11+**、flash.nvim、初回ビルドと更新時に使う make と C コンパイラ
（GCC または Clang）が必要です。公開 Lua/C ヘッダーは同梱されています。
Linux と macOS で検証済みです。Windows は現在サポートしていません。

コアには Unicode の文字そのものによる検索と、任意で有効にできる `latin` source が含まれます。
`sources = {}` は文字そのものの検索のみ、`sources = { "latin" }` はラテン文字の変種も検索します。
ほかの source は別のプラグインとしてインストールします。

- [dirichy/flash-any-japanese.nvim](https://github.com/dirichy/flash-any-japanese.nvim) — かな・漢字・辞書収録語のローマ字検索
- [dirichy/flash-any-pinyin.nvim](https://github.com/dirichy/flash-any-pinyin.nvim) — 中国語の拼音と双拼
- [dirichy/flash-any-nerdfont.nvim](https://github.com/dirichy/flash-any-nerdfont.nvim) — Nerd Font のアイコン名
- [dirichy/flash-any-tiger.nvim](https://github.com/dirichy/flash-any-tiger.nvim) — 中国語の虎碼

デモの source を有効にする lazy.nvim 設定です。`f` には後述の文字モード設定も追加します。

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    "dirichy/flash-any-pinyin.nvim",
    "dirichy/flash-any-japanese.nvim",
    "dirichy/flash-any-nerdfont.nvim",
  },
  build = "make",
  opts = { sources = { "latin", "pinyin", "japanese", "nerdfont" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
    { "<leader>/", function() require("flash-any").search() end, desc = "Flash Any search" },
  },
}
```

不要な source は依存プラグインと sources の両方から外してください。
日本語だけなら latin と japanese を残せます。内蔵 latin に追加プラグインは不要です。
アイコンの表示には端末で Nerd Font を使ってください。

ほかのプラグインマネージャーでは、インストール・更新時にプラグインのディレクトリで
`make` を実行するフックを設定します。vim-plug は `{'do': 'make'}`、packer.nvim は
`run = "make"` です。フックがない場合は手動で make を実行し、依存をロードしてから設定します。

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

C モジュールが未ビルド、またはロードできない場合は make の実行を案内します。
setup は辞書バイナリがなければ生成し、以降はキャッシュを再利用します。
Flash の labels、search、jump などのオプションも setup に渡せます。
`jump(opts)` と `remote(opts)` は sources または binary を含む独立した完全設定で、
setup のフィールドを継承しません。

## 使い方

`s` を押して検索文字列を入力し、表示されたラベルを選びます。
同じ設定で以下のすべてを検索でき、最後の例も一度の検索で続けて入力します。

| 例 | バッファの文字 | 入力 |
| --- | --- | --- |
| ラテン文字のアクセント | café | `cafe` |
| 中国語の拼音 | 中文 | `zhongwen` |
| 日本語のローマ字 | 食べる | `taberu` |
| Nerd Font アイコン |  | `vim` |
| 混在検索 | café 中文 食べる  | `cafe zw taberu vim` |

混在検索の zw は中国語の各文字の頭文字です。スペースは ASCII のまま入力します。
拼音の完全な綴りと頭文字も組み合わせられます。頭文字は最初の一文字なので、
「输」は sh ではなく s です。双拼や各種辞書の設定は、それぞれの source の README を参照してください。
目的の位置にラベルがまだない場合は、入力を続けてください。

後置ラベルの範囲を明確にするため、各行では重ならない検索結果を表示します。
終了位置が早い結果を優先し、同じ終了位置なら短い範囲を選びます。
表示されない候補も、入力を続けると引き続き検索対象になります。

日本語 source は `sushi/susi → 寿司`、`gakkou → 学校`、`nihon/nippon → 日本`、
`taberu → 食べる` などを検索できます。かなの各綴りは音節ごとに組み合わせられます。
詳しい範囲と設定は [日本語 source](https://github.com/dirichy/flash-any-japanese.nvim) にあります。

オペレーター待機モードで `yr` を押し、検索してラベルを選んでから iw と入力すると、
離れた単語をコピーして元のウィンドウに戻ります。削除には dr を使います。

ASCII の文字そのものによる検索と latin は、f/F/t/T でも Neovim の ignorecase と
smartcase に従います。ignorecase は大文字小文字を無視し、smartcase も有効なら
大文字を含む検索では区別します。設定変更は次の検索から反映されます。

latin では `e → é / é`、`o → ø`、`ae → æ`、`ss → ß` などを検索できます。
大文字の元のコード（É → E、Æ → AE）は保持し、上記の大小文字設定を適用します。
結合文字を含む文字全体を消費します。[ラテン文字の範囲と出典](docs/latin.md)も参照してください。

### 検索モード

`search()` は同じ sources を使い、現在のバッファで次の一致へ移動します。
画面外も対象とし、末尾で先頭へ戻ります。入力中に位置をプレビューし、Enter で確定、
Esc で元の位置へ戻り、Backspace で入力を削除します。ラベルや単一結果の自動確定はありません。
プレビューとハイライトは非同期で分割処理し、入力変更で古い処理を中止します。
Enter は未完了の検索を同期的に完了します。約 2 ms ごとに処理を譲りますが、
非常に長い一行の照合中は中断できず、入力が一時的に止まる場合があります。

プラグインは `search()` API のみを提供し、標準のキーマッピングは登録しません。
上記の lazy.nvim 設定例は `<leader>/` を検索に割り当てています。必要に応じて変更・削除してください。
ほかのプラグインマネージャーでは setup 後に設定できます。

```lua
vim.keymap.set("n", "<leader>/", function() require("flash-any").search() end, { desc = "Flash Any search" })
```

拼音設定なら `zhongwen` で「中文」を検索できます。ASCII 記号は文字どおりに扱い、
正規表現は解釈しません。`search(opts)` は `jump(opts)` と同じ完全な単発設定を受け付けます。
方向と折り返しは `search.forward`、`search.wrap` で変更できます。
標準の `/`、検索レジスター、`n`/`N` は変更しません。

### f/F/t/T の文字移動

このプラグインの setup 後、Flash の設定に次を追加します。

```lua
require("flash").setup({
  modes = {
    char = {
      matcher = function(win, state, range)
        return require("flash-any").char(win, state, range)
      end,
      -- multi_line = false,
    },
  },
})
```

例えば拼音の fz は z で始まるコードと文字 z を検索します。
小鶴双拼では fv が「中」と v を検索します。F/t/T、回数、`;` と `,` の反復、
オペレーターとラベルは Flash が処理します。標準の文字検索に戻すには
modes.char.matcher を外します。このコールバックは Flash への接続で、独自コード matcher ではありません。

## 辞書の設定

外部 source を setup より前にロードし、sources で選びます。

```lua
require("flash-any").setup({
  sources = {
    "latin",
    "pinyin",
    "japanese",
    "nerdfont",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
  },
})
```

| source | 内容と既定の動作 |
| --- | --- |
| latin | ラテン文字の変種、letter |
| pinyin | 完全な拼音と頭文字。scheme 指定時は既定で完全コード |
| japanese | かな・漢字・辞書収録語のローマ字グループ、full_code |
| nerdfont | Nerd Font のアイコン名、prefix |
| tiger | 重みに応じた任意の選択キー。既定で第一候補はスペース、第二候補はセミコロン |

`binary = "/path/flash-any.bin"` で固定出力先を指定できます。ファイルがなければ sources
から構築し、binary だけを指定した場合は既存ファイルを読みます。構築失敗時も旧出力を保持し、
既存の検索は自分のスナップショットを使います。初回構築は setup 中に同期実行します。
現在の v14 形式では古い明示的 binary の再生成が必要です。自動キャッシュは再構築されます。
更新後は make を実行し、Neovim を再起動して新しいモジュールをロードしてください。
明示的な出力には `require("flash-any.build").binary()` も使えます。

matcher は full_code、initial、prefix、letter の四種類です。通常の source はすべて
マッチングに参加し、fallback = true は先行 source に認識されていない文字へのみコードを提供します。
空のコード配列も認識済みとして扱います。共有グループの各音節にも matcher を独立して適用できます。
[グループと converter](docs/sources.md#内部编码组--internal-spelling-groups)を参照してください。

### 独自の辞書

少数の記号には data、大きい辞書には file を使います。明示的 data が合計 200 項目を
超えるとプロセスごとに一度だけ通知します。これは性能の案内で、使用数の制限ではありません。

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent", ["中国"] = "zhongguo" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- converter = "/path/converter.lua",
  },
}
```

Rime、TSV、CSV、空白区切り、Fcitx、IBus の辞書を直接読み込めます。
TSV は一行に一つの文字列とコードを書き、複数コードは行を繰り返します。コンマはそのままの文字です。
converter はビルド時だけ実行する Lua 関数を返すファイルです。
data はコード文字列または配列を受け取り、空でない ASCII コード、または有効なグループ参照・
参照列を使います。グループ名は Unicode、実際の綴りは ASCII です。NUL は使用できません。

文字キーには Unicode 17 の字素や単語を使えます。`á`、`👩‍💻`、中国 などが対象で、
重なった長さの異なる単語も同じ開始位置から検索します。範囲は字素境界に一致し、行をまたがず、
Unicode 正規化はしません。位置は Neovim のバイト列に従い、複合字素の最後まで強調表示します。

初めての拡張には [source 開発手順（英語）](docs/writing-sources.md)、詳細には
[構築 API](docs/sources.md)と[録画テンプレート](demos/README.md)があります。

### 既存辞書の変換

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

入力と Lua 出力パスのみが必須です。format は auto/rime/tsv/tab/csv/space/fcitx/ibus、
encoding は既定で utf-8 です。重複をまとめ、単語のキーを保持したまま直接コンパイルできます。
コードには Tab、改行、NUL を含められません。直接の Lua テーブルはほかの非 NUL ASCII も使えます。
文字列や検索に NUL が含まれる場合の動作は未定義です。

## 開発と計測

[実装と検証](docs/development.md) · [ベンチマーク](docs/benchmarks.md)。
make で C モジュールを構築し、make clean で共有ライブラリを削除します。
Makefile は GNU make 3.81 互換で、Neovim を呼びません。CC、CPPFLAGS、CFLAGS、LDFLAGS を
変更できます。Unicode ヘッダーは同梱し、データ更新時のみ再生成します。
clangd は compile_flags.txt を直接使います。

## ライセンス

コードは [MIT](LICENSE) です。Unicode データは上流のライセンスに従います。
[THIRD_PARTY.md](THIRD_PARTY.md)を参照してください。外部 source は辞書の出典とライセンスを
個別に提供します。[デモの録画方法](demos/README.md)。
