#!/usr/bin/env bash
# Checks that the CLI's camera_pretty and FacePolicy.prettyCameraName agree
# and produce the expected names. Run: bash tests/test_camera_names.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load camera_pretty without running the CLI's main.
eval "$(sed -n '/^camera_pretty() {/,/^}/p' "$here/bin/face-unlock")"

cases=(
  "/dev/v4l/by-id/usb-Razer_Inc_Razer_Kiyo_Pro_Ultra-video-index0|Razer Kiyo Pro Ultra"
  "/dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920_A1B2C3D4-video-index0|HD Pro Webcam C920"
  "/dev/v4l/by-id/usb-Chicony_Electronics_Co._Ltd._Integrated_Camera_0001-video-index0|Chicony Electronics Integrated Camera"
  "/dev/v4l/by-id/usb-Logitech_Inc._Logitech_BRIO_7A3B9C1D-video-index0|Logitech BRIO"
  "/dev/v4l/by-id/usb-SunplusIT_Inc_Integrated_IR_Camera-video-index0|SunplusIT Integrated IR Camera"
  "/dev/v4l/by-path/pci-0000:00:14.0-usb-0:2:1.0-video-index0|0000:00:14.0-usb-0:2:1.0"
)

fail=0
for c in "${cases[@]}"; do
  path=${c%%|*} want=${c#*|}
  got_sh=$(camera_pretty "$path")
  got_js=$(node -e '
    const fs = require("fs")
    const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\s*$/m, "")
    console.log(new Function(src + "; return prettyCameraName")()(process.argv[2]))
  ' "$here/FacePolicy.js" "$path")
  if [[ $got_sh == "$want" && $got_js == "$want" ]]; then
    echo "ok - $want"
  else
    echo "FAIL - $path: want '$want', bash '$got_sh', js '$got_js'"
    fail=1
  fi
done
exit $fail
