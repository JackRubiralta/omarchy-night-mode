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
if [[ -z $step ]]; then cat "$f"; else echo "${step%\%}" >"$f"; fi
EOF
  chmod +x "$W/bin/"*
  export PATH="$W/bin:$PATH"
}

monitors() {
  local m out=() make model
  for m in "$@"; do
    case $m in
    eDP-1) make="LG Display" model="0x07B4" ;;
    DP-2) make="Shenzhen KTC Technology Group" model="H24T27" ;;
    *) make="Generic" model="TV" ;;
    esac
    out+=("{\"name\":\"$m\",\"make\":\"$make\",\"model\":\"$model\",\"description\":\"$make $model\",\"disabled\":false}")
  done
  (IFS=,; echo "[${out[*]}]") >"$MOCK/monitors.json"
}

laptop() { cat "$NIGHT_MODE_SYSFS/class/backlight/intel_backlight/brightness"; }
kbd() { cat "$NIGHT_MODE_SYSFS/class/leds/dell::kbd_backlight/brightness"; }
ddc() { cat "$MOCK/ddc-$1"; }
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
eq "its own level was saved" "$(jq -r '.saved["DP-2"].level' "$NIGHT_MODE_STATE_DIR/state.json")" "70"
monitors eDP-1
"$NM" off >/dev/null
eq "laptop restored with monitor away" "$(laptop)" "240"
eq "unplugged monitor stays pending" "$(jq -r '.saved | keys | join(",")' "$NIGHT_MODE_STATE_DIR/state.json")" "DP-2"
monitors eDP-1 DP-2
"$NM" sync >/dev/null
eq "replugged monitor gets its brightness back" "$(ddc DP-2)" "70"
eq "pending entry cleared" "$(jq -c '.saved' "$NIGHT_MODE_STATE_DIR/state.json")" "{}"
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

echo "info"
setup
contains() { if [[ $2 == *"$3"* ]]; then ok "$1"; else bad "$1" "no '$3' in: $2"; fi; }
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
