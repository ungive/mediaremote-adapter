#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;

# This script dynamically loads the MediaRemoteAdapter dylib and executes
# a command. It's designed to be called by a parent process that provides
# the full path to the dylib.

my $usage = "Usage: $0 <path_to_dylib> <loop|play|pause|...>";
die $usage unless @ARGV >= 2;

my $dylib_path = shift @ARGV;
my $command = shift @ARGV;

unless (-e $dylib_path) {
    die "Dynamic library not found at $dylib_path\n";
}

# Use a temporary package name for DynaLoader
package Temp::Loader;
our @ISA = qw(DynaLoader);
bootstrap Temp::Loader $dylib_path;

# Now we can call the C functions directly
package main;

if ($command eq 'loop') {
    Temp::Loader::loop();
} elsif ($command eq 'play') {
    Temp::Loader::play();
} elsif ($command eq 'pause') {
    Temp::Loader::pause_command();
} elsif ($command eq 'toggle_play_pause') {
    Temp::Loader::toggle_play_pause();
} elsif ($command eq 'next_track') {
    Temp::Loader::next_track();
} elsif ($command eq 'previous_track') {
    Temp::Loader::previous_track();
} elsif ($command eq 'stop') {
    Temp::Loader::stop_command();
} else {
    die "Unknown command: $command\n";
} 