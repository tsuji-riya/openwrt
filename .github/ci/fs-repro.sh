#!/bin/bash
# CI only (not for upstream).
# Reproduce a Firmware Selector (ASU) build for elecom_wrc-2533ghbk2-t with an
# official ImageBuilder, both as it is and with the device definition patched
# to the expanded layout of the PR (IMAGE_SIZE 16064k, factory.bin 7808k).
#
# usage: fs-repro.sh <imagebuilder dir> <output dir> <label>
set -u

IB="$1"
OUT="$2"
LABEL="$3"
PROFILE=elecom_wrc-2533ghbk2-t
MK="$IB/target/linux/ramips/image/mt7621.mk"

# Package list sent by the Firmware Selector (default + device packages + LuCI + ASU)
FS_PACKAGES="apk-mbedtls base-files ca-bundle dnsmasq dropbear firewall4 fstools \
kmod-crypto-hw-eip93 kmod-gpio-button-hotplug kmod-leds-gpio kmod-nft-offload libc \
libgcc libustream-mbedtls logd mtd netifd nftables odhcp6c odhcpd-ipv6only ppp \
ppp-mod-pppoe procd-ujail uboot-envtools uci uclient-fetch urandom-seed urngd \
wpad-basic-mbedtls kmod-mt7615-firmware -uboot-envtools luci luci-app-attendedsysupgrade"
NOWIFI_LUCI="-wpad-basic-mbedtls -kmod-mt7615-firmware luci luci-app-attendedsysupgrade"

mkdir -p "$OUT"
REPORT="$OUT/report-fs-$LABEL.md"

patch_layout() {
	cp "$MK" "$MK.orig"
	python3 - "$MK" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r'define Device/elecom_wrc-2533ghbk2-t\n(.*?)\nendef', s, re.S)
assert m, "device block not found"
blk = m.group(1)
new = blk.replace('IMAGE_SIZE := 7808k', 'IMAGE_SIZE := 16064k')
new = re.sub(r'IMAGE/factory.bin := \$\$\(sysupgrade_bin\) \| check-size \|',
             'IMAGE/factory.bin := $$(sysupgrade_bin) | check-size 7808k |', new)
assert new != blk, "nothing patched (already new layout?)"
s = s[:m.start(1)] + new + s[m.end(1):]
open(p, 'w').write(s)
print(new)
PY
}

run() {
	local name="$1" pkgs="$2"
	local d="$OUT/fs-$LABEL-$name"
	mkdir -p "$d"
	echo "::group::$LABEL $name"
	make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$pkgs" \
		BIN_DIR="$d" EXTRA_IMAGE_NAME="$name" >"$d/make.log" 2>&1
	local rc=$?
	tail -n 20 "$d/make.log"
	echo "::endgroup::"
	local f s fs="-" ss="-"
	f=$(ls "$d"/*"$PROFILE"*-squashfs-factory.bin 2>/dev/null | head -n1)
	s=$(ls "$d"/*"$PROFILE"*-squashfs-sysupgrade.bin 2>/dev/null | head -n1)
	[ -n "$f" ] && fs="$(stat -c%s "$f")"
	[ -n "$s" ] && ss="$(stat -c%s "$s")"
	local big
	big=$(grep -o 'is too big: [0-9]* > [0-9]*' "$d/make.log" | sed 's/is too big: //' | sort -u | tr '\n' ' ')
	[ "$rc" -ne 0 ] && big="make failed (rc=$rc) $big"
	echo "| $name | $ss | $fs | ${big:--} |" >> "$REPORT"
}

{
	echo "## Firmware Selector reproduction: $LABEL"
	echo
	echo "| build | sysupgrade.bin | factory.bin | too big (bytes) |"
	echo "| --- | --- | --- | --- |"
} > "$REPORT"

run asis-fs-default "$FS_PACKAGES"
if ! patch_layout; then
	echo "| patching the device definition failed; new layout not tested | - | - | - |" >> "$REPORT"
	cat "$REPORT"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$REPORT" >> "$GITHUB_STEP_SUMMARY"
	exit 0
fi
run newlayout-fs-default "$FS_PACKAGES"
run newlayout-nowifi-luci "$NOWIFI_LUCI"
mv "$MK.orig" "$MK"

cat "$REPORT"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$REPORT" >> "$GITHUB_STEP_SUMMARY"
exit 0
