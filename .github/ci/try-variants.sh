#!/bin/bash
# CI only (not for upstream).
# Run an OpenWrt ImageBuilder with cumulative package removal sets for
# elecom_wrc-2533ghbk2-t and report which set produces images that fit the
# 7808 KiB OEM "Kernel" partition.
#
# usage: try-variants.sh <imagebuilder dir> <output dir> <label>
set -u

IB="$1"
OUT="$2"
LABEL="$3"
PROFILE=elecom_wrc-2533ghbk2-t
LIMIT=7995392   # 7808 KiB

mkdir -p "$OUT"
REPORT="$OUT/report-$LABEL.md"

V1="-ppp -ppp-mod-pppoe"
V2="$V1 -odhcp6c -odhcpd-ipv6only"
V3="$V2 -kmod-crypto-hw-eip93 -kmod-nft-offload"
V4="$V3 -wpad-basic-mbedtls wpad-mini"
V5="$V3 -wpad-basic-mbedtls -kmod-mt7615-firmware"
V6="$V5 -apk-mbedtls"

names=(v0-default v1-noppp v2-noipv6dhcp v3-nooffload v4-wpadmini v5-nowifi v6-nowifi-noapk)
sets=("" "$V1" "$V2" "$V3" "$V4" "$V5" "$V6")

{
	echo "## $LABEL"
	echo
	echo "Limit: $LIMIT bytes (7808 KiB)"
	echo
	echo "| variant | removed / changed packages | factory.bin | sysupgrade.bin | too big (bytes) |"
	echo "| --- | --- | --- | --- | --- |"
} > "$REPORT"

for i in "${!names[@]}"; do
	n="${names[$i]}"
	p="${sets[$i]}"
	d="$OUT/$LABEL-$n"
	mkdir -p "$d"
	log="$d/make.log"
	echo "::group::$LABEL $n: PACKAGES=\"$p\""
	make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$p" \
		BIN_DIR="$d" EXTRA_IMAGE_NAME="$n" >"$log" 2>&1
	rc=$?
	tail -n 30 "$log"
	echo "::endgroup::"

	f=$(ls "$d"/*"$PROFILE"*-squashfs-factory.bin 2>/dev/null | head -n1)
	s=$(ls "$d"/*"$PROFILE"*-squashfs-sysupgrade.bin 2>/dev/null | head -n1)
	fs="-"; ss="-"
	[ -n "$f" ] && fs="$(stat -c%s "$f")"
	[ -n "$s" ] && ss="$(stat -c%s "$s")"
	big=$(grep -o 'is too big: [0-9]* > [0-9]*' "$log" | sed 's/is too big: //' | sort -u | tr '\n' ' ')
	[ "$rc" -ne 0 ] && big="make failed (rc=$rc) $big"
	echo "| $n | \`${p:-none}\` | $fs | $ss | ${big:--} |" >> "$REPORT"
done

cat "$REPORT"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$REPORT" >> "$GITHUB_STEP_SUMMARY"
exit 0
