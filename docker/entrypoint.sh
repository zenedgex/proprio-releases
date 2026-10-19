#!/bin/sh
# proprio-entrypoint <policy> [proprio serve flags]
# proprio-entrypoint lerobot-server [LeRobot policy-server flags]   (LeRobot async inference, see LEROBOT.md)
#
# PROPRIO_LICENSE       licence key string (absent: evaluation mode, 4 robots per tick)
# PROPRIO_LICENSE_FILE  or a mounted file holding the key
# HF_TOKEN              for gated checkpoints
# PROPRIO_METERING      "local" to record robot-ticks in $PROPRIO_HOME/usage.jsonl, "aws" for AWS Marketplace metering (licensed only)
set -e
if [ -n "$PROPRIO_LICENSE_FILE" ] && [ -f "$PROPRIO_LICENSE_FILE" ]; then
  mkdir -p "$PROPRIO_HOME" && cp "$PROPRIO_LICENSE_FILE" "$PROPRIO_HOME/license"
fi
proprio licence || true
if [ "$1" = "lerobot-server" ]; then exec proprio "$@"; fi
exec proprio serve "$@"
