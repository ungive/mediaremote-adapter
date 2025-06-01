#!/bin/bash
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Usage: $0 [framework-name [function name]]"
    exit 0
fi
FRAMEWORK_NAME="${1:-MediaRemoteAdapter}"
/usr/bin/perl MediaRemoteAdapter.pl "$(realpath ..)/build/$FRAMEWORK_NAME.framework" "${@:2}"
