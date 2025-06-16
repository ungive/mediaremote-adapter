#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;
use File::Spec;
use File::Basename;

# This script dynamically loads the MediaRemoteAdapter.framework and executes
# its `loop` function. It effectively becomes the entitled host process.

die "Usage: $0 /path/to/MediaRemoteAdapter.framework\n" unless @ARGV == 1;

my $framework_path = $ARGV[0];
my $framework_basename = File::Basename::basename($framework_path);
die "Provided path is not a framework: $framework_path\n"
  unless $framework_basename =~ s/\.framework$//;

my $framework_binary = File::Spec->catfile($framework_path, $framework_basename);
die "Framework binary not found at $framework_binary\n" unless -e $framework_binary;

# Load the framework binary
my $handle = DynaLoader::dl_load_file($framework_binary, 0)
  or die "Failed to load framework: $framework_binary\n";

my $function_name = 'loop';

# Find the 'loop' function symbol in the loaded framework
my $symbol = DynaLoader::dl_find_symbol($handle, $function_name)
  or die "Symbol '$function_name' not found in $framework_binary\n";

# Make the C function available to be called from Perl
DynaLoader::dl_install_xsub("main::$function_name", $symbol);

# Execute the loop function. This call will block indefinitely.
eval {
  no strict 'refs';
  &{"main::$function_name"}();
};
if ($@) {
  die "Error executing $function_name: $@\n";
} 