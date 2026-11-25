#!/bin/zsh
# Builds the C engines the tunnel extension links:
#   libtpws.a  zapret's tpws, with main() renamed tpws_main() so it runs on a thread
#   libhev.a   hev-socks5-tunnel (tun2socks): IP packets from the tunnel -> SOCKS5 -> tpws
# Output: Native/build/<platform>/lib*.a for iphoneos and iphonesimulator (arm64).
# Rebuilds only when a source file is newer than the library.
set -euo pipefail
here=${0:A:h:h}
out="$here/Native/build"
min=26.0
tpws_src="$here/Vendor/zapret/tpws"
hev_src="$here/Vendor/hev-socks5-tunnel"

newer() { [[ ! -f $1 || -n "$(find "$2" -newer "$1" -type f -name '*.[ch]' | head -1)" ]]; }

for sdk in iphoneos iphonesimulator; do
  dest="$out/$sdk"
  mkdir -p "$dest"
  cc=(xcrun --sdk $sdk clang -arch arm64 -m${sdk/iphoneos/iphoneos}-version-min=$min)
  [[ $sdk == iphonesimulator ]] && cc=(xcrun --sdk $sdk clang -arch arm64 -mios-simulator-version-min=$min)

  if newer "$dest/libtpws.a" "$tpws_src"; then
    echo "building tpws for $sdk"
    obj="$dest/tpws-obj"; rm -rf "$obj"; mkdir -p "$obj"
    for f in "$tpws_src"/*.c "$tpws_src"/epoll-shim/src/*.c "$here/Native/ios_compat.c"; do
      $cc -std=gnu99 -Os -ffunction-sections -fdata-sections -Wno-address-of-packed-member \
        -Wno-deprecated-declarations -Dmain=tpws_main \
        -I"$here/Native/shim" -I"$tpws_src/epoll-shim/include" -I"$tpws_src/macos" \
        -c "$f" -o "$obj/$(basename ${f:h})-$(basename $f .c).o"
    done
    rm -f "$dest/libtpws.a"
    xcrun libtool -static -o "$dest/libtpws.a" "$obj"/*.o 2>/dev/null
    rm -rf "$obj"
  fi

  if newer "$dest/libhev.a" "$hev_src/src"; then
    echo "building hev-socks5-tunnel for $sdk"
    work="$dest/hev-work"; rm -rf "$work"; mkdir -p "$work"
    rsync -a --exclude .git "$hev_src/" "$work/"
    flags="-arch arm64 $([[ $sdk == iphoneos ]] && echo -miphoneos-version-min=$min || echo -mios-simulator-version-min=$min)"
    make -s -C "$work" PP="xcrun --sdk $sdk clang" CC="xcrun --sdk $sdk clang" \
      CFLAGS="$flags" LFLAGS="$flags" static >/dev/null
    rm -f "$dest/libhev.a"
    xcrun libtool -static -o "$dest/libhev.a" "$work/bin/libhev-socks5-tunnel.a" \
      "$work/third-part/lwip/bin/liblwip.a" "$work/third-part/yaml/bin/libyaml.a" \
      "$work/third-part/hev-task-system/bin/libhev-task-system.a" 2>/dev/null
    rm -rf "$work"
  fi
done
echo "native libraries ready in $out"
