#!/bin/bash
# Regenerates the filler packages pkg/p1 .. pkg/p$N.
#
# The crash is a race between action execution and the analysis of the last
# top-level target, so the graph has to be wide enough for the alias's own
# PACKAGE node to have been dropped by the time its BUILD_DRIVER node runs.
# 600 crashes 5/5; 200 crashes only 3/5.
set -euo pipefail
cd "$(dirname "$0")"
N="${1:-600}"
rm -rf pkg/p[0-9]*
for i in $(seq 1 "$N"); do
  mkdir -p "pkg/p$i"
  {
    echo 'load("@rules_shell//shell:sh_test.bzl", "sh_test")'
    echo ""
    echo "genrule("
    echo "    name = \"gen$i\","
    echo "    outs = [\"out$i.txt\"],"
    echo "    cmd = \"seq 1 500 > \$@\","
    echo ")"
    echo ""
    echo "sh_test("
    echo "    name = \"test$i\","
    echo "    srcs = [\"//pkg:t.sh\"],"
    echo "    data = [\":gen$i\"],"
    echo ")"
  } > "pkg/p$i/BUILD.bazel"
done
echo "generated $N filler packages"
