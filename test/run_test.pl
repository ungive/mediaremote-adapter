#!/usr/bin/perl

use strict;
use warnings;

# This script acts as an entitled launcher for a given executable.
# It uses Perl's `com.apple.perl` bundle identifier to grant the
# child process access to the MediaRemote framework.

if (@ARGV < 1) {
    die("Usage: $0 /path/to/executable [args...]\n");
}

# Execute the command passed as arguments, replacing the Perl process.
# The child process will inherit the execution context.
exec(@ARGV) or die("Could not execute command: $!"); 