#!/usr/bin/perl
# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use DynaLoader;
use File::Spec;
use File::Basename;

die "Framework path not provided" unless @ARGV >= 1;

my $framework_path = $ARGV[0];
my $framework_basename = File::Basename::basename($framework_path);
die "Provided path is not a framework: $framework_path\n"
  unless $framework_basename =~ s/\.framework$//;

my $framework = File::Spec->catfile($framework_path, $framework_basename);
die "Framework not found at $framework\n" unless -e $framework;

my $handle = DynaLoader::dl_load_file($framework, 0)
  or die "Failed to load framework: $framework\n";
my $function_name = $ARGV[1] // 'stream';
die "Invalid function name: '$function_name'\n"
  unless $function_name eq 'get'
  || $function_name eq 'stream'
  || $function_name eq 'send';

my $symbol_name = "adapter_$function_name";
if ($function_name eq 'send') {
  my $id = $ARGV[2];
  die "Missing ID for send command" unless defined $id;
  $ENV{"MEDIAREMOTEADAPTER_${symbol_name}_0_command"} = "$id";
  $symbol_name = "${symbol_name}_env";
}

my $symbol = DynaLoader::dl_find_symbol($handle, "$symbol_name")
  or die "Symbol '$symbol_name' not found in $framework\n";
DynaLoader::dl_install_xsub("main::$function_name", $symbol);

eval {
  no strict 'refs';
  &{"main::$function_name"}();
};
if ($@) {
  die "Error executing $function_name: $@\n";
}
