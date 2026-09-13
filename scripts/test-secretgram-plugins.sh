#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc submodules/SettingsUI/Sources/SecretGram/SecretGramPluginStore.swift tests/secretgram-plugins/main.swift -o "$test_dir/plugin-tests"
"$test_dir/plugin-tests"
