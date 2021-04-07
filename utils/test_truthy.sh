#!/bin/sh
set -eu

. ../vars.sh

fail() {
    echo $1
    exit 1
}

A=
set +u
if truthy "${A}"; then fail 1 ;fi
set -u
if truthy "${A:-}"; then fail 22;fi

A=""
set +u
if truthy "${A}"; then fail 2 ;fi
set -u
if truthy "${A:-}"; then fail 23 ;fi

A=false
if truthy "${A}"; then fail 3 ;fi

A="false"
if truthy "${A}"; then fail 4 ;fi

A="0"
if truthy "${A}"; then fail 5 ;fi

A=0
if truthy "${A}"; then fail 6 ;fi

A=1
if ! truthy "${A}"; then fail 7 ;fi

A=true
if ! truthy "${A}"; then fail 8 ;fi

A="true"
if ! truthy "${A}"; then fail 9 ;fi

A=no
if truthy "${A}"; then fail 11 ;fi

A=yes
if ! truthy "${A}"; then fail 12;fi

A="Yes"
if ! truthy "${A}"; then fail 13; fi

A="yEs"
if ! truthy "${A}"; then fail 14; fi

A="yeS"
if ! truthy "${A}"; then fail 15; fi

A="YEs"
if ! truthy "${A}"; then fail 16; fi

A="yES"
if ! truthy "${A}"; then fail 17; fi

A="YES"
if ! truthy "${A}"; then fail 18; fi

A="No"
if truthy "${A}"; then fail 19; fi

A="nO"
if truthy "${A}"; then fail 20; fi

A="NO"
if truthy "${A}"; then fail 21; fi

A="
"
if ! truthy "${A}"; then fail 24; fi

echo "All tests passed!"
