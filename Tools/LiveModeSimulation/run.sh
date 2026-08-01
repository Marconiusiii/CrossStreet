#!/bin/sh
#
# Builds and runs the Live Mode Overpass fetch simulation.
#
# Usage, from anywhere in the repository:
#
#     Tools/LiveModeSimulation/run.sh
#
# The build output goes to a temporary directory, so nothing is left behind in
# the repository. See Documentation/LiveMode.md for what the numbers mean.

set -e

directory=$(cd "$(dirname "$0")" && pwd)
binary=$(mktemp -d)/livesim

swiftc -O \
	"$directory/CachePolicy.swift" \
	"$directory/Traces.swift" \
	"$directory/main.swift" \
	-o "$binary"

"$binary"
