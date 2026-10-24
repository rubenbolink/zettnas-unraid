#!/bin/bash
# Use at your own risk: this writes directly to physical memory (/dev/mem).
# Zettlab D6 Ultra fan control for Unraid. Writes EC fan regs at 0xFE0B0456 via /dev/mem.
# Verified 2026-10-24 on a D6 Ultra (Unraid 7.3.4).
# PWM 0..183 (183=100%). CPU fan is NOT left on auto (EC auto kept it off under Unraid).
BASE=$((0xFE0B0456))
PWM1=$((BASE+2)); PWM2=$((BASE+5)); PWM3=$((BASE+8))   # disks 1, disks 2, CPU
D_MIN=70;  D_MAX=183; T_LO=35; T_HI=48; T_PANIC=55       # disk fans vs hottest HDD
C_MIN=90;  C_MAX=183; C_LO=50; C_HI=80                   # CPU fan vs coretemp
INTERVAL=10
LOG=/var/log/zettlab-fans.log

wr() { printf "\\x$(printf %02x "$2")" | dd of=/dev/mem bs=1 seek="$1" count=1 conv=notrunc status=none; }
full() { wr $PWM1 183; wr $PWM2 183; wr $PWM3 183; }
trap 'full; exit' INT TERM EXIT
curve() { # val lo hi min max
  if [ "$1" -le "$2" ]; then echo $4; elif [ "$1" -ge "$3" ]; then echo $5
  else echo $(( $4 + ($1-$2)*($5-$4)/($3-$2) )); fi; }
hdd_max() { local m=0 t d
  for d in /dev/sd[a-z]; do [ -b "$d" ] || continue
    t=$(smartctl -n standby -A "$d" 2>/dev/null | awk '$1==194||$1==190{print $10; exit}')
    [ -n "$t" ] && [ "$t" -gt "$m" ] && m=$t
  done; echo $m; }
cpu_temp() { local h; for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat $h/name 2>/dev/null)" = coretemp ] && { echo $(( $(cat $h/temp1_input)/1000 )); return; }
  done; echo 99; }   # unknown -> treated as hot

full; sleep 5
while true; do
  H=$(hdd_max); C=$(cpu_temp)
  if [ "$H" -ge $T_PANIC ]; then PD=$D_MAX; else PD=$(curve $H $T_LO $T_HI $D_MIN $D_MAX); fi
  PC=$(curve $C $C_LO $C_HI $C_MIN $C_MAX)
  wr $PWM1 $PD; wr $PWM2 $PD; wr $PWM3 $PC
  echo "$(date '+%F %T') hdd=${H}C cpu=${C}C disk_pwm=$PD cpu_pwm=$PC" > $LOG
  sleep $INTERVAL
done
