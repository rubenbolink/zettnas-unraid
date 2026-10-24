#!/bin/bash
# Zettlab EC fan test. Usage: fan-test.sh            -> read RPMs
#                              fan-test.sh <0-183>    -> set all fans to fixed PWM, then read
# Stop zettlab-fans.sh first (pkill -f zettlab-fans.sh) or it overrides you within 10 s.
BASE=$((0xFE0B0456))
rd() { dd if=/dev/mem bs=1 skip="$1" count=1 status=none | od -An -tu1 | tr -d ' '; }
wr() { printf "\\x$(printf %02x "$2")" | dd of=/dev/mem bs=1 seek="$1" count=1 conv=notrunc status=none; }
if [ -n "$1" ]; then
  [ "$1" -ge 0 ] && [ "$1" -le 183 ] || { echo "PWM must be 0-183"; exit 1; }
  for o in 2 5 8; do wr $((BASE+o)) "$1"; done; echo "Set PWM=$1"; sleep 5
fi
for f in "Disk fan 1:0" "Disk fan 2:3" "CPU fan:6"; do
  o=${f##*:}; hi=$(rd $((BASE+o))); lo=$(rd $((BASE+o+1)))
  echo "${f%%:*}: $(( hi*256 + lo )) RPM (pwm=$(rd $((BASE+o+2))))"
done
