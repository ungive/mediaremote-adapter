#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;
use File::Spec;
use File::Basename;
use Cwd 'abs_path';
use FindBin;

# This script dynamically loads the MediaRemoteAdapter dylib and executes
# a command. It's designed to be called by a parent process that provides
# the full path to the dylib.

my $usage = "Usage: $0 <path_to_dylib> <loop|play|pause|...|set_time TIME>";
die $usage unless @ARGV >= 2;

my $dylib_path = shift @ARGV;
my $command = shift @ARGV;

unless (-e $dylib_path) {
    die "Dynamic library not found at $dylib_path\n";
}

bootstrap MediaRemoteAdapter $dylib_path;

if (not defined $command) {
    die "A command is required.\n$usage\n";
}

if ($command eq 'loop') {
    MediaRemoteAdapter::loop();
} elsif ($command eq 'play') {
    MediaRemoteAdapter::play();
} elsif ($command eq 'pause') {
    MediaRemoteAdapter::pause_command();
} elsif ($command eq 'toggle_play_pause') {
    MediaRemoteAdapter::toggle_play_pause();
} elsif ($command eq 'next_track') {
    MediaRemoteAdapter::next_track();
} elsif ($command eq 'previous_track') {
    MediaRemoteAdapter::previous_track();
} elsif ($command eq 'stop') {
    MediaRemoteAdapter::stop_command();
} elsif ($command eq 'set_time') {
    my $time = $ARGV[0];
    die "Missing time argument for set_time\n" unless defined $time;
    $ENV{'MEDIAREMOTE_SET_TIME'} = $time;
    MediaRemoteAdapter::set_time_from_env();
} else {
    die "Unknown command: $command\n";
} 