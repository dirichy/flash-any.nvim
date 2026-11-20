# ⚡ flash-any.nvim

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

> **마이그레이션 중이며, 현재는 불안정합니다.** `main`은 C 매칭 코어와 새로운 설정 API를 사용합니다.
> 이전 버전은 [master 브랜치 README](https://github.com/dirichy/flash-any.nvim/blob/master/README.old.md)를 참고하세요.

라틴 문자 변형, 중국어 병음, 일본어 로마자, 한글 두벌식 키 입력, 아이콘 이름 또는 사용자 정의 코드로 이동합니다.
[flash.nvim](https://github.com/folke/flash.nvim)을 기반으로 하며 실행 중의 매칭은 모두 C에서 처리합니다.

![s 이동, f 연속 이동, 원격 삭제 및 화면 밖 혼합 검색](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.gif)

[고화질 MP4](https://github.com/dirichy/flash-any.nvim/releases/download/demos/demo.mp4) · [재생 검증 보고서](https://github.com/dirichy/flash-any.nvim/releases/download/demos/verification.json)

데모는 중국어·한글·아이콘을 찾는 `s` 레이블 이동, 여러 source의 공통 첫 키를 쓰는
`fz`와 `f` 연속 이동, `dr` 원격 삭제, 화면 밖 혼합 검색 순서로 진행됩니다.
계속 입력하면 비슷한 후보를 건너뛰고 더 구체적인 대상으로 이동합니다.

## 설치와 설정

Neovim **0.11+**, flash.nvim, 최초 빌드와 업데이트에 필요한 make 및 C 도구 체인
(GCC 또는 Clang)이 필요합니다. 공개 Lua/C 헤더는 포함되어 있습니다.
Linux와 macOS에서 검증했으며 Windows는 현재 지원하지 않습니다.

코어에는 Unicode 문자 그대로의 매칭과 선택적으로 활성화하는 `latin` source가 포함됩니다.
`sources = {}`는 문자 그대로의 매칭만 사용하고, `sources = { "latin" }`은 라틴 문자 변형도 찾습니다.
나머지 source는 별도 플러그인으로 설치합니다.

- [dirichy/flash-any-korean.nvim](https://github.com/dirichy/flash-any-korean.nvim) — 현대 한글 두벌식 키 입력
- [dirichy/flash-any-pinyin.nvim](https://github.com/dirichy/flash-any-pinyin.nvim) — 중국어 병음과 솽핀(双拼)
- [dirichy/flash-any-japanese.nvim](https://github.com/dirichy/flash-any-japanese.nvim) — 가나·한자·사전 단어의 일본어 로마자
- [dirichy/flash-any-nerdfont.nvim](https://github.com/dirichy/flash-any-nerdfont.nvim) — Nerd Font 아이콘 이름
- [dirichy/flash-any-tiger.nvim](https://github.com/dirichy/flash-any-tiger.nvim) — 중국어 Tiger 자형 코드

데모의 source를 사용하는 lazy.nvim 설정입니다. `f`에는 아래의 문자 이동 설정도 추가하세요.

```lua
{
  "dirichy/flash-any.nvim",
  branch = "main",
  version = false,
  dependencies = {
    "folke/flash.nvim",
    "dirichy/flash-any-pinyin.nvim",
    "dirichy/flash-any-japanese.nvim",
    "dirichy/flash-any-korean.nvim",
    "dirichy/flash-any-nerdfont.nvim",
  },
  build = "make",
  opts = { sources = { "latin", "pinyin", "japanese", "korean", "nerdfont" } },
  keys = {
    { "s", mode = { "n", "x", "o" }, function() require("flash-any").jump() end },
    { "r", mode = "o", function() require("flash-any").remote() end },
    { "<leader>/", function() require("flash-any").search() end, desc = "Flash Any search" },
  },
}
```

필요 없는 source는 의존성과 sources 목록 양쪽에서 제거하세요. 한국어만 필요하면
latin과 korean을 남기면 됩니다. Tiger 사용자는 pinyin 대신 tiger를 선택할 수 있습니다.
내장 latin은 추가 플러그인이 필요하지 않습니다. 아이콘을 표시하려면 터미널에 Nerd Font를 설정하세요.

다른 관리자는 설치·업데이트 시 플러그인 디렉터리에서 `make`를 실행하도록 설정합니다.
vim-plug는 `{'do': 'make'}`, packer.nvim은 `run = "make"`를 사용합니다.
빌드 훅이 없다면 설치·업데이트 후 직접 make를 실행하고, 의존성을 로드한 뒤 설정하세요.

```lua
require("flash-any").setup({ sources = {} })
vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash-any").jump() end)
```

미리 빌드한 C 모듈이 없거나 로드할 수 없으면 make 실행을 안내합니다.
setup은 사전 바이너리가 없을 때 바로 생성하며, 이후 시작 시에는 캐시를 재사용합니다.
`labels`, `search`, `jump` 같은 Flash 옵션도 setup에 전달할 수 있습니다.
`jump(opts)`와 `remote(opts)`는 sources 또는 binary를 포함하는 독립적인 전체 설정을 사용하며
setup의 필드를 상속하지 않습니다.

## 사용법

`s`를 누르고 검색 입력을 작성한 다음 표시된 레이블을 선택합니다.
같은 설정으로 다음 예제를 모두 검색할 수 있습니다. 마지막 예제도 검색을 한 번만 시작하고 계속 입력합니다.

| 예제 | 버퍼의 텍스트 | 입력 |
| --- | --- | --- |
| 라틴 문자 변형 | café | `cafe` |
| 중국어 병음 | 中文 | `zhongwen` |
| 일본어 로마자 | 食べる | `taberu` |
| 한글 두벌식 | 한글 | `gksrmf` |
| Nerd Font 아이콘 |  | `vim` |
| 혼합 입력 | café 中文 한글 食べる  | `cafe zw gksrmf taberu vim` |

혼합 입력에서 zw는 중국어 각 글자의 병음 첫 글자이고, 공백은 ASCII 그대로 입력합니다.
병음 전체와 첫 글자를 함께 사용할 수도 있습니다. 첫 글자만 사용하므로 输는 sh가 아닌 s입니다.
솽핀과 기타 사전 옵션은 각 source 문서에 있습니다. 원하는 위치에 레이블이 없으면 계속 입력하세요.

후행 레이블이 가리키는 범위를 구분하기 쉽도록 각 줄에는 겹치지 않는 결과를 표시합니다.
먼저 끝나는 결과를 우선하고, 끝 위치가 같으면 더 짧은 결과를 선택합니다.
표시되지 않은 다른 후보도 계속 입력할 때 매칭에 참여합니다.

연산자 대기 모드에서 `dr`을 누르고 대상을 검색해 레이블을 선택한 뒤 `iW`를 입력하면,
떨어진 단어를 삭제하고 원래 위치로 돌아옵니다. 데모가 이 동작을 보여 줍니다.
삭제 대신 복사하려면 `yr`을 사용하세요. `iW`는 공백으로 구분된 단어 전체를 선택하므로
한자와 가나가 섞인 일본어 단어에도 사용할 수 있습니다.

ASCII 문자 그대로의 매칭과 latin은 `f/F/t/T`에서도 Neovim의 `ignorecase`와 `smartcase`를 따릅니다.
ignorecase는 대소문자를 무시하며, smartcase도 켜져 있으면 대문자가 포함된 입력은 구분합니다.
옵션 변경은 다음 매칭부터 반영됩니다.

latin을 활성화하면 `e → é / é`, `o → ø`, `ae → æ`, `ss → ß` 등을 검색합니다.
대문자는 원래 대문자 코드(`É → E`, `Æ → AE`)를 유지하며 위 옵션을 적용합니다.
결합 문자는 전체 자소와 함께 소비합니다. [라틴 문자 범위와 출처](docs/latin.md)를 참고하세요.

### 한글 입력

한글은 로마자 표기가 아닌 두벌식 키 배열로 검색합니다. 영문 입력 상태에서
`gksrmf → 한글`, `dkssud → 안녕`을 사용할 수 있으며 한글 입력기를 켤 필요가 없습니다.
기본 `full_code`는 `rk → 가`와 `Rk → 까`를 `ignorecase` / `smartcase`와 관계없이 구분합니다.
일반적인 한글 텍스트 입력에는 여전히 한글 입력기가 필요합니다.

현대 한글 11,172개 음절과 정규 분해형, 현대 조합 자모 및 호환 자모를 지원합니다.
자세한 범위와 제한은 [한글 source](https://github.com/dirichy/flash-any-korean.nvim)를 참고하세요.

### 검색 모드

`search()`는 같은 source로 현재 버퍼의 다음 결과를 찾으며 화면 밖도 검색합니다.
끝에 도달하면 처음으로 돌아갑니다. 입력 중 대상을 미리 보고, Enter로 확정하고,
Esc로 원래 위치에 돌아가며, Backspace로 입력을 지웁니다.
레이블이 없고 결과가 하나만 남아도 자동 확정하지 않습니다.

미리 보기와 강조는 비동기 배치로 처리하며 입력이 바뀌면 이전 검색을 취소합니다.
Enter는 남은 작업을 동기적으로 완료합니다. 각 배치는 약 2ms 후 제어권을 돌려주지만,
매우 긴 한 줄의 매칭은 중간에 끊을 수 없어 입력이 잠시 멈출 수 있습니다.

플러그인은 기본 키 매핑 없이 search() API를 제공합니다. 위 lazy.nvim 예제는
`<leader>/`에 연결하며 원하는 키로 바꾸거나 제거할 수 있습니다.
다른 플러그인 관리자는 setup 뒤에 다음 매핑을 추가하세요.

```lua
vim.keymap.set("n", "<leader>/", function() require("flash-any").search() end, { desc = "Flash Any search" })
```

병음을 설정하면 `zhongwen`으로 中文을 검색할 수 있습니다. ASCII 문장 부호는 그대로 검색하며
정규식 문법은 없습니다. `search(opts)`도 sources 또는 binary를 포함하는 전체 일회성 설정을 받습니다.
`search.forward`와 `search.wrap`으로 방향과 순환을 조절합니다.
이 API는 기본 `/`, 검색 레지스터, 기본 `n`/`N` 동작을 바꾸지 않습니다.

### 문자 이동 f/F/t/T

이 플러그인의 setup 뒤에 **Flash 설정**을 추가합니다.

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

`fz`는 코드의 첫 키가 z인 글자와 문자 z를 찾습니다. flypy 솽핀에서는 `fv`로 中과 v를 찾습니다.
Flash가 F/t/T, 횟수, `;`/`,` 반복, 연산자와 레이블을 처리합니다.
기본 문자 매칭으로 돌아가려면 modes.char.matcher를 제거하세요.
이 콜백은 Flash에 연결하는 역할만 하며 사용자 정의 코드 matcher가 아닙니다.

## 사전 설정

setup에서 source를 선택합니다. latin은 내장되어 있으며 중국어·일본어·한국어·아이콘 source는
위 플러그인을 setup 전에 로드해야 합니다.

```lua
require("flash-any").setup({
  sources = {
    "latin",
    "pinyin",
    "japanese",
    "korean",
    "nerdfont",
    -- { name = "pinyin", scheme = "flypy", fuzzy = true },
    -- { name = "tiger" },
  },
})
```

| source | 내용과 기본 동작 |
| --- | --- |
| `latin` | 라틴 문자 변형, `letter` |
| `pinyin` | 병음 전체와 첫 글자. scheme 설정 시 기본값은 전체 코드 |
| `japanese` | 가나·한자·사전 단어 읽기의 로마자 그룹, `full_code` |
| `korean` | 현대 한글 두벌식, 대소문자를 구분하는 `full_code` |
| `nerdfont` | Nerd Font 아이콘 이름, `prefix` |
| `tiger` | 가중치 순 선택 키. 기본값은 첫 후보 공백, 둘째 후보 세미콜론 |

`binary = "/path/flash-any.bin"`으로 고정 출력 경로를 지정할 수 있습니다.
파일이 없으면 sources로 생성하며, binary만 지정하면 기존 파일을 로드합니다.
생성 실패 시 기존 출력을 유지하고 진행 중인 검색은 원래 스냅샷을 계속 사용합니다.
첫 컴파일은 setup에서 동기적으로 수행합니다. 현재 v14 형식에는 오래된 명시적 binary의 재생성이 필요하며
자동 캐시는 스스로 갱신됩니다. 업데이트 후 make를 실행하고 Neovim을 다시 시작하세요.
`require("flash-any.build").binary()`는 명시적 내보내기와 개발에도 사용할 수 있습니다.

솽핀, fuzzy 발음 옵션과 기본 선택 키는 각 source의 설정이며 해당 문서에서 설명합니다.
source의 matcher는 `full_code`, `initial`, `prefix`, `letter` 중 하나입니다.
일반 source는 모두 매칭에 참여합니다. `fallback = true`인 source는 앞선 source가
인식하지 않은 자소에만 코드를 제공합니다. 빈 코드 배열도 인식으로 취급하여 뒤의 fallback을 막습니다.

source는 철자 그룹을 공유하고 음절 시퀀스로 조합할 수 있습니다.
선택한 matcher에 따라 각 음절에 전체 코드, 첫 글자 또는 접두 매칭을 독립적으로 적용합니다.
[그룹 시퀀스와 converter](docs/sources.md#内部编码组--internal-spelling-groups)를 참고하세요.

### 사용자 사전

문장 부호와 소수의 기호에는 data, 사전 파일에는 file을 사용하세요.
명시적인 data source가 합쳐서 200개 텍스트 항목을 넘으면 자동 캐시 검사 시 프로세스당 한 번 경고합니다.
같은 텍스트의 여러 코드는 하나로 셉니다. 성능 안내이며 사용 제한은 아닙니다.

```lua
sources = {
  { data = { ["👩‍💻"] = { "dev", "coder" }, ["á"] = "accent", ["中国"] = "zhongguo" }, matcher = "prefix" },
  {
    file = "/path/table.dict.yaml",
    matcher = "full_code",
    -- Optional build-time code conversion
    -- converter = "/path/converter.lua",
  },
}
```

외부 프로젝트의 Rime, TSV, CSV, 공백 구분, Fcitx, IBus 파일을 그대로 사용할 수 있습니다.
정렬, Lua 상용 글자 테이블 또는 source 모듈이 필요하지 않습니다.
TSV 한 행에는 텍스트와 코드 하나를 넣고, 코드가 여러 개면 텍스트를 반복합니다.
코드의 쉼표는 구분자가 아닌 실제 문자입니다. 선택적인 converter는 Lua 파일이 반환하는 변환 함수이며
빌드 시에만 실행합니다. [연결과 converter](docs/sources.md),
[녹화와 README 템플릿](demos/README.md#第三方码表--third-party-tables)을 참고하세요.

data는 단일 코드 문자열 또는 배열을 받습니다. 코드는 비어 있지 않은 NUL 없는 ASCII 문자열이거나,
Unicode 이름을 쓰는 유효한 그룹 참조·시퀀스여야 합니다. 그룹의 실제 철자는 ASCII입니다.
Lua 팩토리와 빌드 시 변환으로 테이블을 생성할 수도 있습니다.
처음 만드는 source는 [개발 절차](docs/writing-sources.md)를,
전체 옵션은 [빌드 API](docs/sources.md)를 참고하세요.

키는 `á`, `👩‍💻`, 中国처럼 완전한 Unicode 17 자소 또는 구문일 수 있습니다.
단일 문자와 길이가 다른 겹치는 구문이 모두 매칭에 참여하며, 구문 코드를 소비한 뒤 다음 텍스트로 계속 진행할 수 있습니다.
매칭은 완전한 자소 경계에서 시작하고 끝나며 줄을 넘지 않습니다. 자동 Unicode 정규화는 하지 않습니다.
바이트 위치는 Neovim 규칙을 따르며 복합 자소의 마지막 코드 포인트까지 강조합니다.

### 기존 사전 변환

```vim
:FlashAnyBuildTable source.dict common.lua [full.tsv|-] [common-from.lua|-] [format] [encoding]
:checkhealth flash-any
```

입력 파일과 Lua 출력 경로만 필수입니다. format은 auto/rime/tsv/tab/csv/space/fcitx/ibus,
encoding은 기본 utf-8입니다. 중복 항목은 합치고 원래 구문 키를 유지하며 구문 수를 보고합니다.
코드에는 탭, 줄바꿈, NUL을 넣을 수 없습니다. 직접 작성한 Lua 테이블에는 NUL 외의 다른 ASCII 바이트를 넣을 수 있습니다.
NUL이 포함된 텍스트나 쿼리의 매칭 동작은 정의되어 있지 않습니다.

## 개발과 측정

[현재 구현과 검증](docs/development.md) · [벤치마크](docs/benchmarks.md).

make로 C 모듈을 빌드하고 make clean으로 공유 라이브러리를 제거합니다.
Makefile은 GNU make 3.81 문법과 호환되며 Neovim을 호출하지 않습니다.
CC, CPPFLAGS, CFLAGS, LDFLAGS를 재정의할 수 있습니다.
Unicode 헤더 src/grapheme_data.h는 저장소에 포함되며 유지 관리자가 데이터를 갱신할 때만 다시 생성합니다.
clangd는 compile_flags.txt를 직접 사용하므로 compilation database를 만들 필요가 없습니다.

## 라이선스

프로젝트 코드는 [MIT](LICENSE)입니다. Unicode 데이터는 원래 라이선스를 유지합니다.
[THIRD_PARTY.md](THIRD_PARTY.md)를 참고하세요. 각 독립 source는 자신의 데이터 출처와 라이선스를 제공합니다.
[데모 녹화](demos/README.md).
