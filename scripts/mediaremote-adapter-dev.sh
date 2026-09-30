#!/bin/bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
/usr/bin/perl \
    "$SCRIPT_DIR/../bin/mediaremote-adapter.pl" \
    "$SCRIPT_DIR/../build/MediaRemoteAdapter.framework" \
    "$SCRIPT_DIR/../build/MediaRemoteAdapterTestClient" \
    $@
