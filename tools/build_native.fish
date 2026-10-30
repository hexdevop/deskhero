#!/usr/bin/env fish
# Сборка нативного модуля (macOS): universal arm64+x86_64, минимум macOS 13, ad-hoc подпись.
# Нужны только Apple clang (Command Line Tools) и godot в PATH. Сеть не используется.

set root (path resolve (status dirname)/..)
set inc $root/build/native/include
set out $root/native/bin/libdeskhero_native.macos.dylib

if test (uname) != Darwin
    echo "build_native: только macOS" >&2
    exit 1
end

mkdir -p $inc (dirname $out)
# Заголовок берём у установленного движка, чтобы он совпадал с версией
if not test -f $inc/gdextension_interface.h
    begin
        cd $inc; and godot --headless --dump-gdextension-interface >/dev/null 2>&1
    end
    if not test -f $inc/gdextension_interface.h
        echo "build_native: не удалось получить gdextension_interface.h из godot" >&2
        exit 1
    end
end

clang -dynamiclib -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-unknown-warning-option -Wno-cast-function-type-mismatch \
    -fvisibility=hidden -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
    -I $inc -framework AppKit \
    -install_name @rpath/libdeskhero_native.macos.dylib \
    -o $out $root/native/deskhero_native.m
or exit 1

codesign --force --sign - $out
or exit 1

lipo -archs $out
echo "готово: $out"
