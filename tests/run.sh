#!/usr/bin/env bash
# Tests for bin/night-mode. They run against a fake /sys and mock hyprctl,
# brightnessctl and omarchy-brightness-display, so they never touch real screens.
#   tests/run.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NM="$ROOT/bin/night-mode"
FIX="$ROOT/tests/fixtures"
PASS=0 FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

# --- fake system -------------------------------------------------------------

setup() {
  W=$(mktemp -d)
  export NIGHT_MODE_SYSFS="$W/sys" NIGHT_MODE_STATE_DIR="$W/state"
  export NIGHT_MODE_SHELL_JSON="$W/shell.json" XDG_RUNTIME_DIR="$W/run" MOCK="$W/mock"
  unset NIGHT_MODE_BRIGHTNESS NIGHT_MODE_KEYBOARD
  mkdir -p "$W/sys/class/drm/card0-eDP-1" "$W/sys/class/drm/card1-DP-2" "$W/sys/class/drm/card1-HDMI-A-1" \
    "$W/sys/class/backlight/intel_backlight" "$W/sys/class/leds/dell::kbd_backlight" "$W/bin" "$MOCK" "$W/run"
  cp "$FIX/lg-2880x1800.edid" "$W/sys/class/drm/card0-eDP-1/edid"
  cp "$FIX/ktc-h24t27.edid" "$W/sys/class/drm/card1-DP-2/edid"
  # A TV with only the base block (no luminance data) and its own product code.
  { head -c 10 "$FIX/ktc-h24t27.edid"; printf '\x99'; tail -c +12 "$FIX/ktc-h24t27.edid" | head -c 117; } \
    >"$W/sys/class/drm/card1-HDMI-A-1/edid"
  echo 240 >"$W/sys/class/backlight/intel_backlight/brightness"
  echo 400 >"$W/sys/class/backlight/intel_backlight/max_brightness"
  echo 2 >"$W/sys/class/leds/dell::kbd_backlight/brightness"
  echo 2 >"$W/sys/class/leds/dell::kbd_backlight/max_brightness"
  echo 70 >"$MOCK/ddc-DP-2"
  echo 55 >"$MOCK/ddc-HDMI-A-1"
  echo '{"bar":{"layout":{"centerEnd":[{"id":"io.github.jackrubiralta.night-mode"}]}}}' >"$NIGHT_MODE_SHELL_JSON"
  monitors eDP-1 DP-2

  cat >"$W/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
cat "$MOCK/monitors.json"
EOF
  cat >"$W/bin/omarchy-hw-display" <<'EOF'
#!/usr/bin/env bash
echo intel_backlight
EOF
  cat >"$W/bin/brightnessctl" <<'EOF'
#!/usr/bin/env bash
dev="" val=""
while (( $# )); do
  case $1 in -d) dev=$2; shift 2 ;; set) val=$2; shift 2 ;; *) shift ;; esac
done
for f in "$NIGHT_MODE_SYSFS"/class/{backlight,leds}/"$dev"/brightness; do
  [[ -e $f ]] && { echo "$val" >"$f"; exit 0; }
done
exit 1
EOF
  cat >"$W/bin/omarchy-brightness-display" <<'EOF'
#!/usr/bin/env bash
mon="" step=""
while (( $# )); do
  case $1 in --no-osd) shift ;; --monitor) mon=$2; shift 2 ;; *) step=$1; shift ;; esac
done
if [[ $mon == eDP-* ]]; then              # Omarchy drives the laptop backlight in %
  bl="$NIGHT_MODE_SYSFS/class/backlight/intel_backlight"
  if [[ -z $step ]]; then echo $(( $(<"$bl/brightness") * 100 / $(<"$bl/max_brightness") ))
  else echo $(( ${step%\%} * $(<"$bl/max_brightness") / 100 )) >"$bl/brightness"; fi
  exit 0
fi
f="$MOCK/ddc-$mon"
[[ -f $f ]] || exit 1                      # no DDC/CI on this monitor
# Like Omarchy's DDC helper: a monitor that missed a read is refused for 60 s.
mark="$XDG_RUNTIME_DIR/omarchy-brightness-display-ddc/$mon.bus"
if [[ -f $mark ]] && read -r word _ <"$mark" && [[ $word == unavailable ]]; then exit 1; fi
if [[ -f $MOCK/asleep-$mon ]]; then         # still waking up: misses N calls
  n=$(<"$MOCK/asleep-$mon")
  if (( n > 0 )); then
    echo $(( n - 1 )) >"$MOCK/asleep-$mon"
    mkdir -p "${mark%/*}"; echo "unavailable $(date +%s)" >"$mark"
    exit 1
  fi
fi
if [[ -n $step && -f $MOCK/drop-$mon ]]; then  # the monitor misses N writes, silently
  n=$(<"$MOCK/drop-$mon")
  if (( n > 0 )); then echo $(( n - 1 )) >"$MOCK/drop-$mon"; exit 0; fi
fi
if [[ -z $step ]]; then cat "$f"; else echo "${step%\%}" >"$f"; fi
EOF
  chmod +x "$W/bin/"*
  export PATH="$W/bin:$PATH"
}

# monitors eDP-1 DP-2 ... ; "eDP-1:off" is a laptop panel switched off (lid closed).
monitors() {
  local m out=() make model off
  for m in "$@"; do
    off=false
    [[ $m == *:off ]] && { m=${m%:off}; off=true; }
    case $m in
    eDP-1) make="LG Display" model="0x07B4" ;;
    DP-2) make="Shenzhen KTC Technology Group" model="H24T27" ;;
    *) make="Generic" model="TV" ;;
    esac
    out+=("{\"name\":\"$m\",\"make\":\"$make\",\"model\":\"$model\",\"description\":\"$make $model\",\"disabled\":$off}")
  done
  (IFS=,; echo "[${out[*]}]") >"$MOCK/monitors.json"
}

# Move a monitor to another port: its EDID and its own brightness go with it.
move() {
  mkdir -p "$NIGHT_MODE_SYSFS/class/drm/card1-$2"
  mv "$NIGHT_MODE_SYSFS/class/drm/card1-$1/edid" "$NIGHT_MODE_SYSFS/class/drm/card1-$2/edid"
  : >"$NIGHT_MODE_SYSFS/class/drm/card1-$1/edid"   # sysfs keeps an empty file
  mv "$MOCK/ddc-$1" "$MOCK/ddc-$2"
}

laptop() { cat "$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"; }
kbd() { cat "$NIGHT_MODE_SYSFS/class/leds/dell::kbd_backlight/brightness"; }
ddc() { cat "$MOCK/ddc-$1"; }
# The own level saved for the screen now (or last) on a port.
own() { jq -r --arg c "$1" '[.saved[] | select(.connector == $c)][0].level' "$NIGHT_MODE_STATE_DIR/state.json"; }
saved_count() { jq -r '.saved | length' "$NIGHT_MODE_STATE_DIR/state.json"; }
sync_rc() { "$NM" sync >/dev/null 2>&1; echo $?; }
teardown() { rm -rf "$W"; }

# --- tests -------------------------------------------------------------------

echo "EDID"
setup
# shellcheck disable=SC1090
source <(sed -n '/^calc()/,/^# --- settings/p' "$NM")
# shellcheck disable=SC2034 # read by the sourced functions
SYSFS=$NIGHT_MODE_SYSFS
eq "laptop panel: DisplayID brightness range" "$(edid_luminance "$FIX/lg-2880x1800.edid")" $'400.0000\tEDID brightness range'
eq "monitor: CTA HDR frame average" "$(edid_luminance "$FIX/ktc-h24t27.edid")" $'282.8427\tEDID HDR frame average'
if edid_luminance "$W/sys/class/drm/card1-HDMI-A-1/edid" >/dev/null; then bad "base block only has no luminance" "parsed"; else ok "base block only has no luminance"; fi
eq "half float 400" "$(half_float 64 94)" "400.0000"
eq "half float 0.0005" "$(half_float 24 16)" "0.0005"
eq "CTA code value 96 = 400 cd/m²" "$(cta_luminance 96)" "400.0000"
eq "EDID identity" "$(edid_key "$FIX/ktc-h24t27.edid")" "4d67102401000000"
eq "sysfs-style file found" "$(edid_file DP-2)" "$W/sys/class/drm/card1-DP-2/edid"
teardown

echo "on / off"
setup
eq "toggle on prints on" "$("$NM")" "on"
eq "monitor dimmed to 1 %" "$(ddc DP-2)" "1"
eq "laptop matched to the monitor's 1 % (16.8 cd/m² -> 17/400)" "$(laptop)" "17"
eq "keyboard dimmed to lowest step" "$(kbd)" "1"
eq "target recorded" "$(jq -r '.target | . * 10 | round / 10' "$NIGHT_MODE_STATE_DIR/state.json")" "16.8"
eq "status on" "$("$NM" status)" "on"
eq "on again is a no-op" "$("$NM" on)" "on"
eq "toggle off prints off" "$("$NM")" "off"
eq "monitor restored" "$(ddc DP-2)" "70"
eq "laptop restored" "$(laptop)" "240"
eq "keyboard restored" "$(kbd)" "2"
eq "nothing left saved" "$(jq -c '.saved' "$NIGHT_MODE_STATE_DIR/state.json")" "{}"
teardown

echo "remembered target and hotplug"
setup
"$NM" on >/dev/null; "$NM" off >/dev/null
monitors eDP-1
"$NM" on >/dev/null
eq "laptop alone keeps the monitor's target" "$(laptop)" "17"
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "monitor plugged in while on is dimmed" "$(ddc DP-2)" "1"
eq "its own level was saved" "$(own DP-2)" "70"
monitors eDP-1
"$NM" off >/dev/null
eq "laptop restored with monitor away" "$(laptop)" "240"
eq "unplugged monitor stays pending" "$(jq -r '[.saved[].connector] | join(",")' "$NIGHT_MODE_STATE_DIR/state.json")" "DP-2"
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "replugged monitor gets its brightness back" "$(ddc DP-2)" "70"
eq "pending entry cleared" "$(jq -c '.saved' "$NIGHT_MODE_STATE_DIR/state.json")" "{}"
teardown

echo "monitor comes back bright while on"
setup
"$NM" on >/dev/null
monitors eDP-1
echo 100 >"$MOCK/ddc-DP-2"                 # unplugged, powers up at its own brightness
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "replugged monitor is dimmed again" "$(ddc DP-2)" "1"
eq "its own level is still the first one" "$(own DP-2)" "70"
echo 1 >"$MOCK/ddc-DP-2"; echo 9 >"$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"
"$NM" sync >/dev/null
eq "a screen you dimmed further is left alone" "$(laptop)" "9"
"$NM" off >/dev/null
eq "off restores the monitor's own level" "$(ddc DP-2)" "70"
teardown

echo "first run with a laptop only"
setup
monitors eDP-1
"$NM" on >/dev/null
eq "laptop goes to its own 1 %" "$(laptop)" "4"
teardown

echo "settings"
setup
echo '{"bar":{"layout":{"centerEnd":[{"id":"io.github.jackrubiralta.night-mode","brightness":50,"keyboard":"off"}]}}}' >"$NIGHT_MODE_SHELL_JSON"
"$NM" on >/dev/null
eq "laptop at 50 cd/m²" "$(laptop)" "50"
eq "monitor at 50 cd/m² (13 %)" "$(ddc DP-2)" "13"
eq "keyboard off" "$(kbd)" "0"
"$NM" off >/dev/null
eq "keyboard back" "$(kbd)" "2"
NIGHT_MODE_KEYBOARD=unchanged "$NM" on >/dev/null
eq "keyboard unchanged" "$(kbd)" "2"
"$NM" off >/dev/null
NIGHT_MODE_BRIGHTNESS=bogus NIGHT_MODE_KEYBOARD=bogus "$NM" on >/dev/null
eq "bad values fall back to automatic" "$(laptop)" "17"
eq "bad keyboard value falls back to dim" "$(kbd)" "1"
teardown

echo "screens without data or control"
setup
monitors eDP-1 DP-2 HDMI-A-1
rm "$MOCK/ddc-DP-2"   # this monitor has no DDC/CI
"$NM" on >/dev/null
eq "HDMI TV with no EDID luminance uses 250 cd/m² -> 1 %" "$(ddc HDMI-A-1)" "1"
eq "laptop matches the TV's 1 % (14.9 cd/m² -> 15/400)" "$(laptop)" "15"
eq "monitor without DDC/CI marked" "$(jq -r '[.displays[] | select(.connector == "DP-2")][0].controllable' "$NIGHT_MODE_STATE_DIR/state.json")" "false"
"$NM" off >/dev/null
eq "TV restored" "$(ddc HDMI-A-1)" "55"
teardown

echo "migration from 1.0 prototype state"
setup
mkdir -p "$NIGHT_MODE_STATE_DIR"
printf 'display eDP-1 60\nkbd dell::kbd_backlight 2\n' >"$NIGHT_MODE_STATE_DIR/saved"
eq "old state reads as on" "$("$NM" status)" "on"
echo 17 >"$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"
"$NM" off >/dev/null
eq "old saved level restored (60 % through Omarchy)" "$(laptop)" "240"
if [[ ! -e $NIGHT_MODE_STATE_DIR/saved ]]; then ok "old file removed"; else bad "old file removed" "still there"; fi
eq "keyboard from old state restored" "$(kbd)" "2"
teardown

echo "only ever dims"
setup
echo 8 >"$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"
"$NM" on >/dev/null
eq "laptop already darker than 17/400 stays at 8" "$(laptop)" "8"
eq "monitor still dims to 1 %" "$(ddc DP-2)" "1"
contains() { if [[ $2 == *"$3"* ]]; then ok "$1"; else bad "$1" "no '$3' in: $2"; fi; }
contains "info says the laptop keeps its level" "$("$NM" info)" "night     8/400 (already darker than the night level, 17/400, so it stays)"
"$NM" off >/dev/null
eq "laptop back to its own 8" "$(laptop)" "8"
eq "monitor back to 70 %" "$(ddc DP-2)" "70"
echo 1 >"$MOCK/ddc-DP-2"
echo 1 >"$NIGHT_MODE_SYSFS/class/leds/dell::kbd_backlight/brightness"
"$NM" on >/dev/null
eq "monitor already at 1 % stays" "$(ddc DP-2)" "1"
eq "keyboard already on its lowest step stays" "$(kbd)" "1"
"$NM" off >/dev/null
echo 0 >"$NIGHT_MODE_SYSFS/class/leds/dell::kbd_backlight/brightness"
"$NM" on >/dev/null
eq "unlit keyboard stays unlit" "$(kbd)" "0"
"$NM" off >/dev/null
teardown

echo "hand-dimmed during night mode"
setup
"$NM" on >/dev/null
echo 5 >"$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"   # brightness key
echo '{"bar":{"layout":{"centerEnd":[{"id":"io.github.jackrubiralta.night-mode","brightness":30}]}}}' >"$NIGHT_MODE_SHELL_JSON"
"$NM" sync >/dev/null
eq "a higher night level does not raise a hand-dimmed screen" "$(laptop)" "5"
echo '{"bar":{"layout":{"centerEnd":[{"id":"io.github.jackrubiralta.night-mode","brightness":4}]}}}' >"$NIGHT_MODE_SHELL_JSON"
"$NM" sync >/dev/null
eq "a lower night level still dims further" "$(laptop)" "4"
"$NM" off >/dev/null
eq "off still restores the level from before night mode" "$(laptop)" "240"
"$NM" on >/dev/null
echo 120 >"$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"   # turned up by hand
"$NM" sync >/dev/null
eq "a laptop turned up by hand is not dimmed again by a sync" "$(laptop)" "120"
"$NM" off >/dev/null
eq "off still gives its level from before night mode" "$(laptop)" "240"
teardown

echo "restores are checked"
setup
"$NM" on >/dev/null
echo 1 >"$MOCK/drop-DP-2"
eq "a missed write is retried" "$("$NM" off 2>/dev/null)" "off"
eq "monitor back to 70 % after the retry" "$(ddc DP-2)" "70"
"$NM" on >/dev/null
echo 99 >"$MOCK/drop-DP-2"
eq "a monitor that will not take its level keeps night mode on" "$("$NM" off 2>/dev/null)" "on"
eq "laptop still restored meanwhile" "$(laptop)" "240"
eq "monitor's own level kept" "$(own DP-2)" "70"
eq "second miss in a row lets night mode go off" "$("$NM" toggle 2>/dev/null)" "off"
eq "monitor's own level still kept" "$(own DP-2)" "70"
echo 0 >"$MOCK/drop-DP-2"
"$NM" sync >/dev/null
eq "next sync puts it back" "$(ddc DP-2)" "70"
eq "and clears it" "$(jq -c '.saved' "$NIGHT_MODE_STATE_DIR/state.json")" "{}"
"$NM" on >/dev/null
echo 2 >"$MOCK/drop-DP-2"
"$NM" off >/dev/null 2>&1
eq "two missed writes within one restore are still retried" "$(ddc DP-2)" "70"
teardown

echo "a screen away is treated as plugged in"
setup
"$NM" on >/dev/null
monitors eDP-1                             # unplug the laptop (monitor keeps its 1 %)
"$NM" sync >/dev/null
"$NM" off >/dev/null                       # undim on the laptop alone
eq "laptop restored on its own" "$(laptop)" "240"
eq "monitor's own level kept while it is away" "$(own DP-2)" "70"
monitors eDP-1 DP-2                        # plug back in: still at 1 %, slow to wake
echo 6 >"$MOCK/asleep-DP-2"
eq "sync says try again while the monitor does not answer" "$(sync_rc)" "75"
eq "monitor not answering yet, still saved" "$(own DP-2)" "70"
eq "sync after it wakes" "$(sync_rc)" "0"
eq "monitor gets its own level back" "$(ddc DP-2)" "70"
eq "nothing left saved" "$(saved_count)" "0"
teardown

setup
"$NM" on >/dev/null; monitors eDP-1; "$NM" off >/dev/null
monitors eDP-1 DP-2
mkdir -p "$XDG_RUNTIME_DIR/omarchy-brightness-display-ddc"
echo "unavailable $(date +%s)" >"$XDG_RUNTIME_DIR/omarchy-brightness-display-ddc/DP-2.bus"
echo 1 >"$MOCK/asleep-DP-2"
eq "Omarchy's 60 s 'unavailable' mark does not block a monitor that answered before" "$(sync_rc)" "0"
eq "and it is restored" "$(ddc DP-2)" "70"
teardown

setup
"$NM" on >/dev/null; monitors eDP-1; "$NM" off >/dev/null
"$NM" on >/dev/null; "$NM" off >/dev/null  # on and off again while it is away
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "still its own level from before, after more on/off while away" "$(ddc DP-2)" "70"
teardown

setup
"$NM" on >/dev/null; monitors eDP-1; "$NM" off >/dev/null
"$NM" on >/dev/null                        # night mode on again before it comes back
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "back while on: stays dimmed" "$(ddc DP-2)" "1"
"$NM" off >/dev/null
eq "then off gives the level from before it left" "$(ddc DP-2)" "70"
teardown

echo "a screen on another port"
setup
"$NM" on >/dev/null
monitors eDP-1; "$NM" sync >/dev/null; "$NM" off >/dev/null
move DP-2 DP-1                             # plugged into the other USB-C port
monitors eDP-1 DP-1
"$NM" sync >/dev/null
eq "same monitor on another port gets its own level back" "$(ddc DP-1)" "70"
eq "nothing left saved" "$(saved_count)" "0"
teardown

setup
"$NM" on >/dev/null
monitors eDP-1; "$NM" sync >/dev/null
move DP-2 DP-1
monitors eDP-1 DP-1
"$NM" sync >/dev/null
eq "on another port while on: stays dimmed" "$(ddc DP-1)" "1"
eq "its own level is not taken from the dimmed one" "$(own DP-1)" "70"
"$NM" off >/dev/null
eq "off gives it 70 % on the new port" "$(ddc DP-1)" "70"
teardown

setup
"$NM" on >/dev/null
monitors eDP-1; "$NM" off >/dev/null       # monitor away, its restore pending
move DP-2 DP-1                             # park the monitor; a TV takes its port
cp "$NIGHT_MODE_SYSFS/class/drm/card1-HDMI-A-1/edid" "$NIGHT_MODE_SYSFS/class/drm/card1-DP-2/edid"
echo 55 >"$MOCK/ddc-DP-2"
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "another screen on that port is left alone" "$(ddc DP-2)" "55"
eq "the monitor's own level is still kept" "$(own DP-2)" "70"
mv "$MOCK/ddc-DP-1" "$MOCK/ddc-DP-2"
cp "$NIGHT_MODE_SYSFS/class/drm/card1-DP-1/edid" "$NIGHT_MODE_SYSFS/class/drm/card1-DP-2/edid"
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "the monitor back on its port gets its level" "$(ddc DP-2)" "70"
teardown

echo "state from 1.1"
setup
mkdir -p "$NIGHT_MODE_STATE_DIR"
echo 1 >"$MOCK/ddc-DP-2"
echo '{"on":false,"saved":{"DP-2":{"key":"4d67102401000000","kind":"percent","device":"","level":70,"setLevel":1}},"displays":{}}' \
  >"$NIGHT_MODE_STATE_DIR/state.json"
move DP-2 DP-1
monitors eDP-1 DP-1
"$NM" sync >/dev/null
eq "a 1.1 entry filed under its old port finds the monitor" "$(ddc DP-1)" "70"
eq "and is cleared" "$(saved_count)" "0"
teardown

echo "a monitor that misses a read"
setup
"$NM" on >/dev/null
echo 3 >"$MOCK/asleep-DP-2"
eq "sync asks to try again" "$(sync_rc)" "75"
eq "laptop keeps the monitor-matched level (no darker target)" "$(laptop)" "17"
eq "monitor still counts as controllable" "$(jq -r '.displays["4d67102401000000"].controllable' "$NIGHT_MODE_STATE_DIR/state.json")" "true"
teardown

setup
"$NM" on >/dev/null
monitors eDP-1
echo 100 >"$MOCK/ddc-DP-2"; echo 1 >"$MOCK/asleep-DP-2"
monitors eDP-1 DP-2                        # comes back bright and slow
eq "bright and not answering: try again" "$(sync_rc)" "75"
"$NM" sync >/dev/null
eq "dimmed once it answers" "$(ddc DP-2)" "1"
teardown

echo "lid closed"
setup
"$NM" on >/dev/null
monitors eDP-1:off DP-2                    # lid closed, laptop panel switched off
"$NM" off >/dev/null
eq "laptop backlight restored with the lid closed" "$(laptop)" "240"
eq "monitor restored" "$(ddc DP-2)" "70"
"$NM" on >/dev/null
eq "laptop dimmed with the lid closed, ready for when it opens" "$(laptop)" "17"
teardown

echo "two identical monitors"
setup
mkdir -p "$NIGHT_MODE_SYSFS/class/drm/card1-DP-1"
cp "$FIX/ktc-h24t27.edid" "$NIGHT_MODE_SYSFS/class/drm/card1-DP-1/edid"
echo 40 >"$MOCK/ddc-DP-1"
monitors eDP-1 DP-1 DP-2
"$NM" on >/dev/null
eq "first dimmed" "$(ddc DP-1)" "1"
eq "second dimmed" "$(ddc DP-2)" "1"
"$NM" off >/dev/null
eq "first back to its own 40 %" "$(ddc DP-1)" "40"
eq "second back to its own 70 %" "$(ddc DP-2)" "70"
teardown

echo "syncs asked at once"
setup
"$NM" on >/dev/null
monitors eDP-1
"$NM" sync >/dev/null & "$NM" sync >/dev/null & wait
eq "both finish and the laptop is right" "$(laptop)" "17"
teardown

echo "info"
setup
info_text=$("$NM" info)
contains "info shows laptop maximum" "$info_text" "maximum   400 cd/m² (EDID brightness range)"
contains "info shows monitor night level" "$info_text" "night     1 %"
eq "info --json is valid" "$("$NM" info --json | jq -r '.screens | length')" "2"
eq "forget all" "$("$NM" forget)" "Forgot all."
eq "version" "$("$NM" version)" "night-mode $(jq -r .version "$ROOT/manifest.json")"
teardown

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
