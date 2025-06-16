#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;

# --- Autoflush STDOUT ---
# This is critical. It prevents Perl from buffering output and ensures
# that data is sent to the parent Swift process immediately.
$| = 1;

# This script dynamically loads the MediaRemoteAdapter dylib and executes
# a command. It's designed to be called by a parent process that provides
# the full path to the dylib.

print STDERR "[Perl] Script started.\n";

my $usage = "Usage: $0 <path_to_dylib> <loop|play|pause|...>";
die $usage unless @ARGV >= 2;

my $dylib_path = shift @ARGV;
my $command = shift @ARGV;

print STDERR "[Perl] Dylib Path: $dylib_path\n";
print STDERR "[Perl] Command: $command\n";

unless (-e $dylib_path) {
    die "Dynamic library not found at $dylib_path\n";
}

# --- Manual DynaLoader Invocation ---

# 1. Load the library file directly.
my $libref = DynaLoader::dl_load_file($dylib_path)
    or die "Can't load '$dylib_path': " . DynaLoader::dl_error();

# 2. Find and install each C function as a Perl subroutine.
# This avoids any high-level magic and gives us direct control.
sub install_xsub {
    my ($perl_name, $lib) = @_;
    # C functions are usually prefixed with an underscore by the compiler.
    my $c_name = "_" . $perl_name;

    my $symref = DynaLoader::dl_find_symbol($lib, $c_name);
    
    # If the mangled name isn't found, try the plain name as a fallback.
    unless ($symref) {
        $symref = DynaLoader::dl_find_symbol($lib, $perl_name);
    }

    die "Can't find symbol '$perl_name' or '$c_name' in '$dylib_path'" unless $symref;
    
    # Install the C function into the main:: namespace so we can call it.
    DynaLoader::dl_install_xsub("main::" . $perl_name, $symref);
}

# 3. Install all the functions we need from the library.
install_xsub("bootstrap", $libref);
install_xsub("loop", $libref);
install_xsub("play", $libref);
install_xsub("pause_command", $libref);
install_xsub("toggle_play_pause", $libref);
install_xsub("next_track", $libref);
install_xsub("previous_track", $libref);
install_xsub("stop_command", $libref);

# 4. Call the bootstrap function to initialize the C code.
bootstrap();
print STDERR "[Perl] Bootstrap called.\n";

# 5. Execute the requested command by calling the newly installed subroutine.
if ($command eq 'loop') {
    print STDERR "[Perl] Entering loop...\n";
    loop();
} elsif ($command eq 'play') {
    print STDERR "[Perl] Sending play command...\n";
    play();
} elsif ($command eq 'pause') {
    print STDERR "[Perl] Sending pause command...\n";
    pause_command();
} elsif ($command eq 'toggle_play_pause') {
    print STDERR "[Perl] Sending toggle_play_pause command...\n";
    toggle_play_pause();
} elsif ($command eq 'next_track') {
    print STDERR "[Perl] Sending next_track command...\n";
    next_track();
} elsif ($command eq 'previous_track') {
    print STDERR "[Perl] Sending previous_track command...\n";
    previous_track();
} elsif ($command eq 'stop') {
    print STDERR "[Perl] Sending stop command...\n";
    stop_command();
} else {
    die "Unknown command: $command\n";
}

print STDERR "[Perl] Command '$command' executed. Exiting.\n"; 