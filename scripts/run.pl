#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;
use File::Spec;
use File::Basename;
use Cwd 'abs_path';

# This script dynamically loads the MediaRemoteAdapter.framework and executes
# a function within it. It can either start the persistent `loop` to get
# media info, or send a single playback command and exit.

# --- Configuration: Map string commands to the C enum values ---
my %COMMAND_MAP = (
    "toggle" => 1, # kMRTogglePlayPause
    "play"   => 4, # kMRPlay
    "pause"  => 5, # kMRPause
    "stop"   => 6, # kMRStop
    "next"   => 8, # kMRNextTrack
    "prev"   => 9, # kMRPreviousTrack
);

# --- Argument Parsing ---
my $usage = "Usage: $0 /path/to/framework [command] [args...]\n" .
            "Valid commands: loop, play, pause, toggle, next, prev, stop, set_time <seconds>\n";
die $usage unless @ARGV >= 1;

my $framework_path = abs_path(shift @ARGV);
my $command_name   = shift @ARGV // 'loop'; # Default to 'loop'

my $framework_basename = File::Basename::basename($framework_path);
die "Provided path is not a framework: $framework_path\n"
  unless $framework_basename =~ s/\.framework$//;

my $framework_binary = File::Spec->catfile($framework_path, $framework_basename);
die "Framework binary not found at $framework_binary\n" unless -e $framework_binary;

# --- Dynamic Loading ---
my $handle = DynaLoader::dl_load_file($framework_binary, 0)
  or die "Failed to load framework: $framework_binary\n";

# --- Subroutine to call C functions ---
sub execute_c_function {
    my ($func_name, @args) = @_;
    my $symbol = DynaLoader::dl_find_symbol($handle, $func_name)
      or die "Symbol '$func_name' not found in $framework_binary\n";
    DynaLoader::dl_install_xsub("main::$func_name", $symbol);
    eval {
        no strict 'refs';
        &{"main::$func_name"}(@args);
    };
    if ($@) {
        die "Error executing $func_name: $@\n";
    }
}

# --- Command Dispatch ---
if ($command_name eq 'loop') {
    execute_c_function('loop');
}
elsif (exists $COMMAND_MAP{$command_name}) {
    my $command_id = $COMMAND_MAP{$command_name};
    execute_c_function('send_command', $command_id);
    print "Sent command: $command_name\n";
}
elsif ($command_name eq 'set_time') {
    my $time = shift @ARGV;
    die "Usage: ... set_time <seconds>\n" unless defined $time && $time =~ /^[0-9]+(\.[0-9]+)?$/;
    execute_c_function('set_time', $time);
    print "Sent command: set_time to $time seconds\n";
}
else {
    die "Unknown command '$command_name'.\n$usage";
} 