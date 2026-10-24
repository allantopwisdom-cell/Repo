#!/bin/sh
set -e
cd "$(dirname "$0")"
make clean 2>/dev/null || true
make package messages=yes
