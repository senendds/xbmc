#!/bin/bash

[[ -f buildhelpers.sh ]] &&
    source buildhelpers.sh

FFMPEG_CONFIG_FILE=/xbmc/tools/buildsteps/windows/ffmpeg_options.txt
FFMPEG_VERSION_FILE=/xbmc/tools/depends/target/ffmpeg/FFMPEG-VERSION
FFMPEG_BASE_OPTS="--disable-debug --disable-doc --enable-gpl --enable-w32threads"
FFMPEG_DEFAULT_OPTS=""
FFMPEG_TARGET_OS=mingw32

do_loaddeps $FFMPEG_VERSION_FILE
FFMPEGDESTDIR=$PREFIX

do_getFFmpegConfig() {
  if [[ -f "$FFMPEG_CONFIG_FILE" ]]; then
    FFMPEG_OPTS_SHARED="$FFMPEG_BASE_OPTS $(cat "$FFMPEG_CONFIG_FILE" | sed -e 's:\\::g' -e 's/#.*//')"
  else
    FFMPEG_OPTS_SHARED="$FFMPEG_BASE_OPTS $FFMPEG_DEFAULT_OPTS"
  fi

  if [ "$ARCH" == "x86_64" ]; then
    FFMPEG_TARGET_OS=mingw64
  elif [ "$ARCH" == "x86" ]; then
    FFMPEG_TARGET_OS=mingw32
    do_addOption "--cpu=i686"
  elif [ "$ARCH" == "arm" ]; then
    FFMPEG_TARGET_OS=mingw32
    do_addOption "--cpu=armv7"
  fi

  # add options for static modplug
  if do_checkForOptions "--enable-libmodplug"; then
    do_addOption "--extra-cflags=-DMODPLUG_STATIC"
  fi

  # handle gplv3 libs
  if do_checkForOptions "--enable-libopencore-amrwb --enable-libopencore-amrnb \
    --enable-libvo-aacenc --enable-libvo-amrwbenc"; then
    do_addOption "--enable-version3"
  fi

  do_removeOption "--enable-nonfree"
  do_removeOption "--enable-libfdk-aac"
  do_removeOption "--enable-nvenc"
  do_removeOption "--enable-libfaac"

  # remove libs that don't work with shared
  do_removeOption "--enable-decklink"
  do_removeOption "--enable-libutvideo"
  do_removeOption "--enable-libgme"
}

do_checkForOptions() {
  local isPresent=1
  for option in "$@"; do
    for option2 in $option; do
      if echo "$FFMPEG_OPTS_SHARED" | grep -q -E -e "$option2"; then
        isPresent=0
      fi
    done
  done
  return $isPresent
}

do_addOption() {
  local option=${1%% *}
  local shared=$2
  if ! do_checkForOptions "$option"; then
    FFMPEG_OPTS_SHARED="$FFMPEG_OPTS_SHARED $option"
  fi
}

do_removeOption() {
  local option=${1%% *}
  FFMPEG_OPTS_SHARED=$(echo "$FFMPEG_OPTS_SHARED" | sed "s/ *$option//g")
}

do_getFFmpegConfig

# enable OpenSSL, because schannel has issues
do_removeOption "--enable-gnutls"
do_addOption "--disable-gnutls"
do_addOption "--enable-openssl"
do_addOption "--enable-nonfree"
do_addOption "--toolchain=msvc"
do_addOption "--disable-mediafoundation"

if [ "$ARCH" == "x86_64" ]; then
  FFMPEG_TARGET_OS=win64
elif [ "$ARCH" = "x86" ]; then
  FFMPEG_TARGET_OS=win32
elif [ "$ARCH" = "arm" ]; then
  FFMPEG_TARGET_OS=win32
fi

export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS=""

extra_cflags="-I$LOCALDESTDIR/include -I/depends/$TRIPLET/include -DWIN32_LEAN_AND_MEAN"
extra_ldflags="-LIBPATH:\"$LOCALDESTDIR/lib\" -LIBPATH:\"$MINGW_PREFIX/lib\" -LIBPATH:\"/depends/$TRIPLET/lib\""
if [ $win10 == "yes" ]; then
  do_addOption "--enable-cross-compile"
  extra_cflags=$extra_cflags" -MD -DWINAPI_FAMILY=WINAPI_FAMILY_APP -D_WIN32_WINNT=0x0A00"
  extra_ldflags=$extra_ldflags" -APPCONTAINER WindowsApp.lib"
fi

# compile ffmpeg with debug symbols
if do_checkForOptions "--enable-debug"; then
  extra_cflags=$extra_cflags" -MDd"
  extra_ldflags=$extra_ldflags" -NODEFAULTLIB:libcmt"
fi

cd $LOCALBUILDDIR

do_clean_get $1
[ -f config.mak ] && make distclean
cleanLastSuccess $FFMPEGDESTDIR

# FFmpeg 6.0.1 detects MSVC by parsing English "Version" from cl.exe output.
# On localized toolchains (e.g. Spanish "versión"), that leaves cl_major_ver
# empty and configure aborts with "Unsupported MSVC version". Match the first
# major version number instead of the localized word.
#sed -i 's/cl_major_ver=$(cl\.exe 2>\&1 | sed -n '\''s\/\.\*Version \\\(\[\[:digit:\]\]\\{1,\\}\\)\\\.\.\*\/\\\\1\/p'\''))/cl_major_ver=$(cl.exe 2>\&1 | sed -n '\''s\/.* \\([0-9][0-9]*\\)\\..*\/\\1\/p'\'' | head -n 1)/' "$LOCALSRCDIR/configure"
sed -i 's/cl_major_ver=.*/cl_major_ver=19/' "$LOCALSRCDIR/configure"

do_print_status "$LIBNAME-$VERSION (${TRIPLET})" "$blue_color" "Configuring"

[[ -z "$extra_cflags" ]] && extra_cflags=-DPTW32_STATIC_LIB
[[ -z "$extra_ldflags" ]] && extra_ldflags=-static-libgcc

$LOCALSRCDIR/configure --target-os=$FFMPEG_TARGET_OS --prefix=$FFMPEGDESTDIR --arch=$ARCH \
  $FFMPEG_OPTS_SHARED \
  --extra-cflags="$extra_cflags" --extra-ldflags="$extra_ldflags"

do_makelib
exit $?
