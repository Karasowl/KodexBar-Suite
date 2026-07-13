#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v rg >/dev/null 2>&1; then
    echo "rg is required" >&2
    exit 1
fi

jq empty metadata.json tests/fixtures/provider-logic.json
python3 -c 'import xml.etree.ElementTree as ET; ET.parse("contents/config/main.xml")'
bash -n scripts/validate.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/validate.yml")'
node tests/provider-logic.test.js

if command -v qmllint >/dev/null 2>&1; then
    qmllint contents/code/providerLogic.js contents/ui/main.qml contents/ui/config/configGeneral.qml contents/config/config.qml
else
    echo "qmllint is required" >&2
    exit 1
fi

test "$(sha256sum LICENSE | cut -d " " -f 1)" = "c1a297819a29ca2d0ee9c250ce7d915d7951e565a6a41d3c90a3da267eb9c7a7"
test "$(sha256sum screenshot.png | cut -d " " -f 1)" = "1e5232ff5ceab7ff564eb132c94fdb3256249d4064ed4def36da880b36b4c0c8"
test "$(sha256sum contents/fonts/Manrope-Variable.ttf | cut -d " " -f 1)" = "d0639be45d0af36e798172419d7bd173c4bd4f29e2b76cbb69db1d11bf8b0a40"
test "$(sha256sum contents/fonts/OFL.txt | cut -d " " -f 1)" = "e01b637272e0cbdfb240184dd98ea5cc671556d9894dae2668d92ab2c906787c"
test "$(sha256sum contents/icons/providers/codex.svg | cut -d " " -f 1)" = "7a7ce407225e109cb51f3c8ec96fc6c7eaae418c49602904d894d782f7f98027"
test "$(sha256sum contents/icons/providers/openai.svg | cut -d " " -f 1)" = "7a7ce407225e109cb51f3c8ec96fc6c7eaae418c49602904d894d782f7f98027"
test "$(sha256sum contents/icons/providers/claude.svg | cut -d " " -f 1)" = "4f62a1ff873994f344709bf0bc6a24a74734fb23cfe0880bd7790e98a1c4c4ef"
test "$(sha256sum contents/icons/providers/grok.svg | cut -d " " -f 1)" = "40737f7259d8dea54dc55fdd8b9d89fe29d5b016540db6d7e4e1efa074869fa1"
test "$(sha256sum contents/icons/providers/antigravity.svg | cut -d " " -f 1)" = "a85968c0131eba3e5f022188207b0552a36ef56337ab0eebf91abb2091e04893"
test "$(sha256sum contents/icons/providers/gemini.svg | cut -d " " -f 1)" = "088be040b274f8d10b54a87276d1f0666ad98e185e18b1db5ea8d6fb52cb1ff8"

if rg -n --hidden \
    --glob '!LICENSE' \
    --glob '!WORKER_RESULT.md' \
    --glob '!.git' \
    --glob '!.git/**' \
    '(BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{32,}|/home/[A-Za-z0-9._-]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})' .; then
    echo "Potential secret or personal data found" >&2
    exit 1
fi

if rg -n '[—;]' --glob '*.md' --glob '!WORKER_RESULT.md' .; then
    echo "Disallowed prose punctuation found" >&2
    exit 1
fi

if rg -n '[ \t]+$' --hidden \
    --glob '!.git/**' \
    --glob '!WORKER_RESULT.md' \
    --glob '*.{md,qml,js,json,xml,sh,yml,yaml}' \
    .; then
    echo "Trailing whitespace found" >&2
    exit 1
fi

git --git-dir="$repo_root/.git" --work-tree="$repo_root" diff --check
echo "static validation passed"
