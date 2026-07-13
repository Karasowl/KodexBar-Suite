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

if rg -n --hidden \
    --glob '!LICENSE' \
    --glob '!WORKER_RESULT.md' \
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

git diff --check
echo "static validation passed"
