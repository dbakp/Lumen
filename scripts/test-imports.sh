#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift run --scratch-path "${TMPDIR:-/tmp}/LumenLogicBuild" LumenLogicChecks
