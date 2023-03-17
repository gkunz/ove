#!/usr/bin/env bash

set -e

ignore+=" digraph"
ignore+=" export-logs"
ignore+=" image-refresh"
ignore+=" loop-close"
ignore+=" post-push"
ignore+=" post-push-parallel"
ignore+=" pre-push"
ignore+=" refresh"
ignore+=" shell-check"
ignore+=" unsource"

for a in ${OVE_BUILT_INS_WITHOUT_ARGS}; do
	if [[ $ignore == *$a* ]]; then
	       continue
	elif ! ove "$a"; then
		echo "$a failed"
		exit 1
	fi
done
