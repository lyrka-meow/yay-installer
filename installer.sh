#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sudo pacman -Sy --needed base-devel git fvwm3 kitty xdotool gawk xorg-xrandr
git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay"
cd "$tmp/yay"
makepkg -si --noconfirm

cat > "$HOME/.xinitrc" <<'EOF'
exec fvwm3
EOF

mkdir -p "$HOME/.fvwm"

cat > "$HOME/.fvwm/config" <<EOF
EdgeScroll 0 0
ClickTime 0
OpaqueMoveSize unlimited
Mouse 1 R A Nop
Mouse 2 R A Nop
Mouse 3 R A Nop
Key t A 4 Exec exec kitty
Key q A 4 Quit
Key r A 4 Restart
Key z A 4 Exec exec $HOME/.fvwm/toggle_spin.sh
Key x A 4 Exec exec $HOME/.fvwm/toggle_wheel.sh
EOF

cat > "$HOME/.fvwm/toggle_spin.sh" <<'EOF'
#!/usr/bin/env bash
command -v xdotool >/dev/null 2>&1 || exit 1
WID=$(xdotool getactivewindow 2>/dev/null) || exit 0
[ -z "$WID" ] || [ "$WID" = "0" ] && exit 0
DIR="/tmp/fvwm_spin"
mkdir -p "$DIR"
PID_FILE="$DIR/${WID}.pid"
GEOM_FILE="$DIR/${WID}.geom"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    sleep 0.05
  fi
  if [ -f "$GEOM_FILE" ]; then
    read -r OX OY < "$GEOM_FILE"
    xdotool windowmove "$WID" "$OX" "$OY" 2>/dev/null
  fi
  rm -f "$PID_FILE" "$GEOM_FILE"
  exit 0
fi
eval "$(xdotool getwindowgeometry --shell "$WID" 2>/dev/null)" || exit 0
echo "$X $Y" > "$GEOM_FILE"
CX=$X
CY=$Y
(
  angle=0
  r=55
  while true; do
    rr=$(( r + RANDOM % 21 - 10 ))
    jx=$(( RANDOM % 11 - 5 ))
    jy=$(( RANDOM % 11 - 5 ))
    dx=$(awk "BEGIN { rad=$angle*3.14159265/180; printf \"%.0f\", $rr*cos(rad) }")
    dy=$(awk "BEGIN { rad=$angle*3.14159265/180; printf \"%.0f\", $rr*sin(rad) }")
    nx=$(( CX + dx + jx ))
    ny=$(( CY + dy + jy ))
    [ "$nx" -lt 0 ] && nx=0
    [ "$ny" -lt 0 ] && ny=0
    xdotool windowmove "$WID" "$nx" "$ny" 2>/dev/null
    angle=$(( (angle + 8) % 360 ))
    sleep 0.025
  done
) &
echo $! > "$PID_FILE"
EOF

cat > "$HOME/.fvwm/toggle_wheel.sh" <<'EOF'
#!/usr/bin/env bash
command -v xdotool >/dev/null 2>&1 || exit 1
WID=$(xdotool getactivewindow 2>/dev/null)
if [ -z "$WID" ] || [ "$WID" = "0" ]; then
  eval "$(xdotool getmouselocation --shell 2>/dev/null)"
  WID=$(xdotool getwindowatxy "${x:-0}" "${y:-0}" 2>/dev/null)
fi
[ -z "$WID" ] || [ "$WID" = "0" ] && exit 0
DIR="/tmp/fvwm_wheel"
mkdir -p "$DIR"
PID_FILE="$DIR/${WID}.pid"
GEOM_FILE="$DIR/${WID}.geom"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null
  sleep 0.08
  if [ -f "$GEOM_FILE" ]; then
    read -r OX OY OW OH < "$GEOM_FILE"
    xdotool windowsize "$WID" "${OW:-400}" "${OH:-300}" 2>/dev/null
    xdotool windowmove "$WID" "$OX" "$OY" 2>/dev/null
  fi
  rm -f "$PID_FILE" "$GEOM_FILE"
  exit 0
fi
eval "$(xdotool getwindowgeometry --shell "$WID" 2>/dev/null)" || exit 0
echo "$X $Y $WIDTH $HEIGHT" > "$GEOM_FILE"
SCREEN_X=0
SCREEN_Y=0
SCREEN_W=1920
SCREEN_H=1080
read -r SW SH < <(xdotool getdisplaygeometry 2>/dev/null) || true
[ -n "$SW" ] && [ "$SW" -gt 0 ] && SCREEN_W=$SW
[ -n "$SH" ] && [ "$SH" -gt 0 ] && SCREEN_H=$SH
TOTAL_W=${SW:-1920}
TOTAL_H=${SH:-1080}
if command -v xrandr >/dev/null 2>&1; then
  win_cx=$(( X + WIDTH / 2 ))
  win_cy=$(( Y + HEIGHT / 2 ))
  while read -r geom; do
    [ -z "$geom" ] && continue
    mw="${geom%%x*}"; rest="${geom#*x}"; mh="${rest%%+*}"; rest="${rest#*+}"; mx="${rest%%+*}"; my="${rest#*+}"
    [ -z "$mw" ] || [ -z "$mh" ] && continue
    if [ "$win_cx" -ge "$mx" ] && [ "$win_cx" -lt "$(( mx + mw ))" ] && [ "$win_cy" -ge "$my" ] && [ "$win_cy" -lt "$(( my + mh ))" ]; then
      SCREEN_X=$mx
      SCREEN_Y=$my
      SCREEN_W=$mw
      SCREEN_H=$mh
      break
    fi
  done < <(xrandr --query 2>/dev/null | sed -n 's/.* connected[^0-9]*\([0-9][0-9]*x[0-9][0-9]*+[0-9][0-9]*+[0-9][0-9]*\).*/\1/p')
fi
FLOOR_Y=$(( SCREEN_Y + SCREEN_H - HEIGHT ))
[ "$FLOOR_Y" -lt "$SCREEN_Y" ] && FLOOR_Y=$SCREEN_Y
G=5
DAMP=65
ROLL=16
BW=$WIDTH
BH=$HEIGHT
(
  phase="fall"
  x=$X
  y=$Y
  vx=0
  vy=0
  vx_roll=$ROLL
  while true; do
    if [ "$phase" = "fall" ]; then
      vy=$(( vy + G ))
      y=$(( y + vy ))
      x=$(( x + vx ))
      if [ "$y" -ge "$FLOOR_Y" ]; then
        y=$FLOOR_Y
        vy=$(( -vy * DAMP / 100 ))
        if [ "${vy#-}" -lt 25 ]; then
          phase="roll"
          vy=0
        fi
      fi
      if [ "$y" -lt "$SCREEN_Y" ]; then
        y=$SCREEN_Y
        vy=$(( -vy * DAMP / 100 ))
      fi
      if [ "$x" -lt "$SCREEN_X" ]; then
        x=$SCREEN_X
        vx=$(( -vx * DAMP / 100 ))
      fi
      if [ "$x" -ge "$(( SCREEN_X + SCREEN_W - BW ))" ]; then
        x=$(( SCREEN_X + SCREEN_W - BW ))
        vx=$(( -vx * DAMP / 100 ))
      fi
      for oid in $(xdotool search --onlyvisible --name '.*' 2>/dev/null); do
        [ "$oid" = "$WID" ] && continue
        g=$(xdotool getwindowgeometry --shell "$oid" 2>/dev/null)
        ox=$(echo "$g" | grep '^X=' | cut -d= -f2); oy=$(echo "$g" | grep '^Y=' | cut -d= -f2)
        ow=$(echo "$g" | grep '^WIDTH=' | cut -d= -f2); oh=$(echo "$g" | grep '^HEIGHT=' | cut -d= -f2)
        [ -z "$ow" ] || [ "$ow" -le 0 ] && continue
        [ "$ox" = "0" ] && [ "$oy" = "0" ] && [ "$ow" -ge "$TOTAL_W" ] && [ "$oh" -ge "$TOTAL_H" ] && continue
        if [ "$x" -lt $((ox+ow)) ] && [ $((x+BW)) -gt "$ox" ] && [ "$y" -lt $((oy+oh)) ] && [ $((y+BH)) -gt "$oy" ]; then
          olx=$(( (x+BW < ox+ow ? x+BW : ox+ow) - (x > ox ? x : ox) ))
          oly=$(( (y+BH < oy+oh ? y+BH : oy+oh) - (y > oy ? y : oy) ))
          if [ "${olx:-0}" -lt "${oly:-0}" ]; then
            vx=$(( -vx * DAMP / 100 ))
            [ "$x" -lt "$ox" ] && x=$(( ox - BW )) || x=$(( ox + ow ))
          else
            vy=$(( -vy * DAMP / 100 ))
            [ "$y" -lt "$oy" ] && y=$(( oy - BH )) || y=$(( oy + oh ))
          fi
          break
        fi
      done
      xdotool windowmove "$WID" "$x" "$y" 2>/dev/null
    else
      x=$(( x + vx_roll ))
      y=$FLOOR_Y
      if [ "$x" -lt "$SCREEN_X" ]; then x=$SCREEN_X; vx_roll=$(( -vx_roll * DAMP / 100 )); fi
      if [ "$x" -ge "$(( SCREEN_X + SCREEN_W - BW ))" ]; then x=$(( SCREEN_X + SCREEN_W - BW )); vx_roll=$(( -vx_roll * DAMP / 100 )); fi
      for oid in $(xdotool search --onlyvisible --name '.*' 2>/dev/null); do
        [ "$oid" = "$WID" ] && continue
        g=$(xdotool getwindowgeometry --shell "$oid" 2>/dev/null)
        ox=$(echo "$g" | grep '^X=' | cut -d= -f2); oy=$(echo "$g" | grep '^Y=' | cut -d= -f2)
        ow=$(echo "$g" | grep '^WIDTH=' | cut -d= -f2); oh=$(echo "$g" | grep '^HEIGHT=' | cut -d= -f2)
        [ -z "$ow" ] || [ "$ow" -le 0 ] && continue
        [ "$ox" = "0" ] && [ "$oy" = "0" ] && [ "$ow" -ge "$TOTAL_W" ] && [ "$oh" -ge "$TOTAL_H" ] && continue
        if [ "$x" -lt $((ox+ow)) ] && [ $((x+BW)) -gt "$ox" ] && [ "$y" -lt $((oy+oh)) ] && [ $((y+BH)) -gt "$oy" ]; then
          vx_roll=$(( -vx_roll * DAMP / 100 ))
          [ "$x" -lt "$ox" ] && x=$(( ox - BW )) || x=$(( ox + ow ))
          break
        fi
      done
      xdotool windowmove "$WID" "$x" "$y" 2>/dev/null
    fi
    sleep 0.02
  done
) &
echo $! > "$PID_FILE"
EOF

chmod +x "$HOME/.fvwm/toggle_spin.sh" "$HOME/.fvwm/toggle_wheel.sh"
