#!/bin/bash
# Exercises bin/omarchy-displays against fake monitor sets.
#
# The engine reads hardware through OMARCHY_DISPLAYS_HW_JSON when it is set and
# talks to a stub hyprctl, so nothing here touches the running compositor.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/../bin/omarchy-displays"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK"
export PATH="$HERE/stub:$PATH"
export LC_ALL=C

GENERATED="$WORK/.local/state/omarchy/toggles/hypr/zz-display-layout.lua"
TOGGLES="$WORK/.local/state/omarchy/toggles/hypr"

pass=0
fail=0

use() { export OMARCHY_DISPLAYS_HW_JSON="$(cat "$HERE/fixtures/$1.json")"; }
fresh() { rm -rf "$WORK/.local" "$WORK/.config"; }
rules() { grep -v '^--' "$GENERATED" 2>/dev/null | grep -v '^$'; }

check() {
  local what="$1" want="$2" got="$3"
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$what" "$want" "$got" >&2
  fi
}

# Position of one output in the generated config, or "" when it has no rule.
pos() {
  rules | sed -nE 's/.*output = "'"$1"'".*position = "([^"]*)".*/\1/p' | head -1
}
field() {
  rules | sed -nE 's/.*output = "'"$1"'".*'"$2"' = "?([^",}]*)"?.*/\1/p' | head -1
}
has_rule() { rules | grep -q "output = \"$1\""; }

# ---------------------------------------------------------- two heads

use two-heads; fresh

"$ENGINE" extend right >/dev/null
check "extend right: HDMI anchors at the origin" "0x0" "$(pos HDMI-A-1)"
check "extend right: laptop sits to its right" "1920x0" "$(pos eDP-2)"

"$ENGINE" extend left >/dev/null
check "extend left: laptop takes the origin" "0x0" "$(pos eDP-2)"
check "extend left: HDMI moves right of it" "1920x0" "$(pos HDMI-A-1)"

"$ENGINE" extend down >/dev/null
check "extend down: stacks vertically" "0x1080" "$(pos eDP-2)"

"$ENGINE" arrange eDP-2 HDMI-A-1 >/dev/null
check "arrange: honours the given order" "0x0" "$(pos eDP-2)"
check "arrange: second output follows" "1920x0" "$(pos HDMI-A-1)"

"$ENGINE" mirror HDMI-A-1 >/dev/null
check "mirror: source keeps its own rule" "0x0" "$(pos HDMI-A-1)"
check "mirror: the other display clones it" "HDMI-A-1" "$(field eDP-2 mirror)"

# A 4K mode at scale 2 occupies 1920 logical pixels, so its neighbour must
# start there and not at 3840.
"$ENGINE" extend right >/dev/null
"$ENGINE" mode HDMI-A-1 3840x2160@30 >/dev/null
check "explicit mode: neighbour clears the full width" "3840x0" "$(pos eDP-2)"
"$ENGINE" scale HDMI-A-1 2 >/dev/null
check "scale 2: neighbour clears the logical width" "1920x0" "$(pos eDP-2)"

# A 90° rotation swaps the axes, so a 1920x1080 panel becomes 1080 wide.
"$ENGINE" mode HDMI-A-1 preferred >/dev/null
"$ENGINE" scale HDMI-A-1 1 >/dev/null
"$ENGINE" arrange eDP-2 HDMI-A-1 >/dev/null
"$ENGINE" transform eDP-2 90 >/dev/null
check "rotate 90: neighbour clears the rotated width" "1080x0" "$(pos HDMI-A-1)"
"$ENGINE" transform eDP-2 0 >/dev/null

# The order here is still eDP-2 then HDMI-A-1 from the arrange above, and
# both are 1080 tall, so centring changes nothing.
"$ENGINE" align center >/dev/null
check "align center: equal heights need no offset (first)" "0x0" "$(pos eDP-2)"
check "align center: equal heights need no offset (second)" "1920x0" "$(pos HDMI-A-1)"
"$ENGINE" align top >/dev/null

"$ENGINE" only HDMI-A-1 >/dev/null
check "only: the other display is switched off" "disabled" \
  "$(rules | grep -q 'output = "eDP-2", disabled = true' && echo disabled)"

# ---------------------------------------------- guard rails

out=$("$ENGINE" enable HDMI-A-1 off 2>&1); rc=$?
check "the last display cannot be switched off (rc)" "1" "$rc"
check "the last display cannot be switched off (msg)" "Can't disable the only active display" "$out"

"$ENGINE" enable eDP-2 on >/dev/null
out=$("$ENGINE" mirror 2>&1 >/dev/null); rc=$?
check "mirror with two displays succeeds" "0" "$rc"

"$ENGINE" only eDP-2 >/dev/null
out=$("$ENGINE" mirror 2>&1 >/dev/null); rc=$?
check "mirror needs a second enabled display (rc)" "1" "$rc"

# Output names are interpolated into Lua, so a crafted name must be refused
# rather than written out.
before=$(cat "$GENERATED")
out=$("$ENGINE" mode 'eDP-2", mode = "x") os.execute("touch /tmp/pwned' 1920x1080@60 2>&1); rc=$?
check "a name carrying Lua is refused (rc)" "1" "$rc"
check "a name carrying Lua is refused (msg)" "1" \
  "$(grep -qc 'Refusing unsafe monitor name' <<<"$out" && echo 1)"
check "a refused name changes nothing" "same" \
  "$([[ $(cat "$GENERATED") == "$before" ]] && echo same)"

out=$("$ENGINE" scale NOPE-1 2 2>&1 >/dev/null); rc=$?
check "an unknown monitor is rejected" "1" "$rc"
out=$("$ENGINE" scale eDP-2 99 2>&1 >/dev/null); rc=$?
check "an absurd scale is rejected" "1" "$rc"
out=$("$ENGINE" transform eDP-2 45 2>&1 >/dev/null); rc=$?
check "a non-quadrant rotation is rejected" "1" "$rc"
out=$("$ENGINE" position eDP-2 nonsense 2>&1 >/dev/null); rc=$?
check "a malformed position is rejected" "1" "$rc"

# ------------------------------------------------- three heads

use three-heads; fresh
"$ENGINE" arrange DP-1 HDMI-A-1 eDP-2 >/dev/null
# DP-1 is off in hardware, so its width has to come from availableModes.
check "a dark output is measured from its modes" "2560x0" "$(pos HDMI-A-1)"
check "the third output follows both" "4480x0" "$(pos eDP-2)"

"$ENGINE" align center >/dev/null
check "align center offsets the shorter displays" "2560x180" "$(pos HDMI-A-1)"
"$ENGINE" align top >/dev/null

"$ENGINE" arrange --vertical eDP-2 HDMI-A-1 DP-1 >/dev/null
check "vertical arrange stacks downward" "0x1080" "$(pos HDMI-A-1)"
check "vertical arrange continues the stack" "0x2160" "$(pos DP-1)"

"$ENGINE" mirror eDP-2 >/dev/null
check "mirror covers every other head (HDMI)" "eDP-2" "$(field HDMI-A-1 mirror)"
check "mirror covers every other head (DP)" "eDP-2" "$(field DP-1 mirror)"

# ------------------------------------------------------ profiles

"$ENGINE" extend right >/dev/null
"$ENGINE" profile save triple >/dev/null
use two-heads
"$ENGINE" extend left >/dev/null
"$ENGINE" profile save dual >/dev/null
check "profiles are listed" "dual
triple" "$("$ENGINE" profile list)"

# `dual` was captured from `extend left`, which anchors on the primary and so
# puts eDP-2 on the right of HDMI-A-1.
"$ENGINE" mirror HDMI-A-1 >/dev/null
"$ENGINE" profile apply dual >/dev/null
check "applying a profile restores its arrangement (left)" "0x0" "$(pos HDMI-A-1)"
check "applying a profile restores its arrangement (right)" "1920x0" "$(pos eDP-2)"

# `auto` matches on the set of outputs that are plugged in.
"$ENGINE" mirror HDMI-A-1 >/dev/null
"$ENGINE" profile auto >/dev/null
check "auto picks the profile for these heads" "1920x0" "$(pos eDP-2)"
check "auto leaves mirror mode behind" "" "$(field HDMI-A-1 mirror)"

use three-heads
"$ENGINE" profile auto >/dev/null
check "auto follows a change of hardware" "3" "$(rules | wc -l)"

# A manual position survives a per-output tweak but not a repack.
use two-heads; fresh
"$ENGINE" extend right >/dev/null
"$ENGINE" position eDP-2 -1920x200 >/dev/null
check "a manual position is written out" "-1920x200" "$(pos eDP-2)"
"$ENGINE" scale eDP-2 1.25 >/dev/null
check "a per-output tweak keeps it" "-1920x200" "$(pos eDP-2)"
"$ENGINE" extend right >/dev/null
check "a preset repacks over it" "1920x0" "$(pos eDP-2)"

# ---------------------------------------------- compositor interop

# The clamshell watcher owns the internal panel while the lid is shut.
use two-heads; fresh
"$ENGINE" extend right >/dev/null
touch "$TOGGLES/internal-monitor-clamshell.lua"
"$ENGINE" apply
check "clamshell: the internal panel is left alone" "" "$(has_rule eDP-2 && echo present)"
check "clamshell: the external still gets a rule" "0x0" "$(pos HDMI-A-1)"
rm -f "$TOGGLES/internal-monitor-clamshell.lua"

# The built-in laptop toggles write monitor rules of their own; taking over
# has to stand them down rather than race them.
touch "$TOGGLES/internal-monitor-disable.lua" "$TOGGLES/internal-monitor-mirror.lua"
"$ENGINE" apply
check "the built-in laptop toggles are cleared" "zz-display-layout.lua" "$(ls "$TOGGLES")"

# Scale and rotation are not arranged by this plugin, so a generated rule has
# to carry forward whatever the compositor is already doing rather than
# flattening it to 1.
use scaled-head; fresh
"$ENGINE" extend right >/dev/null
check "an existing scale is carried into the generated rule" "1.25" "$(field eDP-2 scale)"
check "an output at the default scale stays there" "1" "$(field HDMI-A-1 scale)"
# 1920 at scale 1.25 is 1536 logical pixels, so whatever sits to the right of
# the laptop starts there and not at 1920.
"$ENGINE" arrange eDP-2 HDMI-A-1 >/dev/null
check "packing uses the scaled width" "1536x0" "$(pos HDMI-A-1)"
"$ENGINE" extend right >/dev/null
"$ENGINE" only HDMI-A-1 >/dev/null
"$ENGINE" enable eDP-2 on >/dev/null
check "the scale survives switching a display off and on" "1.25" "$(field eDP-2 scale)"

# A virtual output is not a monitor anyone can look at. Arranging around one
# shoves the real desktop next to a screen that does not exist, so they are
# filtered out and the session reads as single-head.
use one-head-plus-virtual; fresh
check "a headless output is not counted" "1" "$("$ENGINE" state | jq -r '.connectedCount')"
check "a headless output is not listed" "[\"eDP-2\"]" "$("$ENGINE" state | jq -c '.order')"
out=$("$ENGINE" extend right 2>&1 >/dev/null); rc=$?
check "arranging is declined with one real monitor (rc)" "1" "$rc"
check "arranging is declined with one real monitor (msg)" "1" \
  "$(grep -qc 'needs a second monitor' <<<"$out" && echo 1)"
check "declining wrote no config" "gone" "$([[ -f $GENERATED ]] || echo gone)"
out=$("$ENGINE" arrange HEADLESS-2 eDP-2 2>&1 >/dev/null); rc=$?
check "a headless output cannot be arranged against" "1" "$rc"

# Opting in brings them back, for anyone deliberately driving a virtual screen.
check "virtuals can be opted into" "2" \
  "$(OMARCHY_DISPLAYS_INCLUDE_VIRTUAL=1 "$ENGINE" state | jq -r '.connectedCount')"

# A session that is nothing but virtual outputs still has to be usable.
use only-virtual; fresh
check "an all-virtual session keeps its screens" "1" "$("$ENGINE" state | jq -r '.connectedCount')"

# A blank reply from hyprctl must degrade, not explode.
use no-heads; fresh
check "no monitors: state still parses" "0" "$("$ENGINE" state | jq -r '.connectedCount')"
unset OMARCHY_DISPLAYS_HW_JSON
check "no compositor: state still parses" "0" "$("$ENGINE" state | jq -r '.connectedCount')"

# reset hands control back to monitors.lua
use two-heads; fresh
"$ENGINE" extend right >/dev/null
check "taking over is visible in state" "true" "$("$ENGINE" state | jq -r '.managed')"
"$ENGINE" reset
check "reset removes the generated config" "gone" "$([[ -f $GENERATED ]] || echo gone)"
check "reset is visible in state" "false" "$("$ENGINE" state | jq -r '.managed')"

printf '\n%d checks passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
