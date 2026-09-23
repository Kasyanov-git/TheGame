#!/usr/bin/env bash
# Headless-проверка Sprint 1 на wasm-сборке Godot 4.x через Node.js.
#
# Что делает:
#   1. ставит @ringozz/godot-web-wasm32 (обычный Godot web-рантайм 4.7,
#      собранный emscripten'ом; тянется с npm — доступнее, чем GitHub
#      release assets в CI-песочницах);
#   2. готовит «подготовленную» копию проекта:
#      - main_scene подменяется на tests/smoke.tscn (driver сам грузит
#        src/main/main.tscn и гоняет 13 проверок физики);
#      - у копи-скриптов снимаются аннотации пользовательских классов
#        (runtime-сборка без редактора не имеет
#        .godot/global_script_class_cache.bin, и cross-file class_name
#        типы в ней не резолвятся; в репозитории код ОСТАЁТСЯ типизированным);
#   3. крутит движок headless и возвращает 0, если в консоли «SMOKE: PASS».
#
# Важно: это ИНСТРУМЕНТ CI/песочниц. В обычном dev-workflow достаточно
# открыть проект в Godot 4.3+ (F5) и погонять руками; проверки продублированы
# в самом движке-логике (никаких правок src).
#
# Требования: node >= 20, npm. Запуск из корня репозитория:
#   ./tools/headless/run_smoke.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
WORK=${WORK_DIR:-/tmp/godot-wasm-smoke}
mkdir -p "$WORK"
cd "$WORK"
[ -d node_modules/@ringozz/godot-web-wasm32 ] || npm i --no-audit --no-fund @ringozz/godot-web-wasm32@4.7.2-626 @emnapi/runtime >/dev/null
rm -rf proj && mkdir proj
cp -r "$ROOT/src" "$ROOT/tests" "$ROOT/project.godot" "$ROOT/icon.svg" proj/
sed -i 's|run/main_scene="res://src/main/main.tscn"|run/main_scene="res://tests/smoke.tscn"|' proj/project.godot
# strip user-class type annotations in the COPY (see note above)
find proj -name '*.gd' -print0 | xargs -0 sed -i -E \
  -e 's/ as (ArcadeVehicle|BowlArena|DebugHud|ChaseCameraRig)//g' \
  -e 's/: (ArcadeVehicle|BowlArena|DebugHud|ChaseCameraRig)\b//g' \
  -e 's/:=/=/g'
GODOT_PROJECT="$WORK/proj" NPM_ROOT="$WORK" FRAMES=4000 \
  node --no-warnings "$ROOT/tools/headless/godot-wasm-runner.mjs"
