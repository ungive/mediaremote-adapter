#!/usr/bin/perl
# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

# Usage:
#   mediaremote-adapter.pl FRAMEWORK_PATH [FUNCTION [PARAMS|OPTIONS...]]
#
# FRAMEWORK_PATH:
#   Absolute (!) path to MediaRemoteAdapter.framework
#
# FUNCTION:
#   stream (default): Streams now playing information (as diff by default)
#   get: Prints now playing information once with all available metadata
#   send: Sends a command to the now playing application
#
# PARAMS:
#   send(command)
#     command: The MRCommand ID as a number (e.g. kMRPlay = 0)
#
# OPTIONS:
#   stream
#     --no-diff: Disable diffing and always dump all metadata
#     --debounce=N: Delay in milliseconds to prevent spam (0 by default)
#
# Examples (script name and framework path omitted):
#   stream --no-diff --debounce=100
#   send 2  # Toggles play/pause in the media player (kMRTogglePlayPause)
#

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
my $function_name = $ARGV[1] // "stream";
die "Invalid function name: '$function_name'\n"
  unless $function_name eq "stream"
  || $function_name eq "get"
  || $function_name eq "send";

sub parse_options {
  my ($start_index) = @_;
  my %arg_map;
  for my $i ($start_index .. $#ARGV) {
    my $arg = $ARGV[$i];
    if ($arg =~ /^--([a-z\\-]+)(?:=(.*))?$/) {
      my $key = $1;
      my $value = $2 || undef;
      $arg_map{$key} = $value;
    }
  }
  return \%arg_map;  # Return a reference to the hash
}

sub env_func {
  my $symbol_name = shift;
  return "${symbol_name}_env";
}

sub set_env_param {
  my ($func, $index, $name, $value) = @_;
  $ENV{"MEDIAREMOTEADAPTER_PARAM_${func}_${index}_${name}"} = "$value";
}

sub set_env_option {
  my ($name, $value) = @_;
  $ENV{"MEDIAREMOTEADAPTER_OPTION_${name}"} = defined $value ? "$value" : "";
}

my $symbol_name = "adapter_$function_name";
if ($function_name eq "send") {
  my $id = $ARGV[2];
  die "Missing ID for send command" unless defined $id;
  set_env_param($symbol_name, 0, "command", "$id");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "stream") {
  my $options = parse_options(2);
  foreach my $key (keys %{$options}) {
    if ($key eq "no-diff" && !defined $options->{$key}) {
      set_env_option("no_diff");
    }
    elsif ($key eq "debounce" && defined $options->{$key}) {
      set_env_option("debounce", $options->{$key});
    }
  }
  $symbol_name = env_func($symbol_name);
}

my $symbol = DynaLoader::dl_find_symbol($handle, "$symbol_name")
  or die "Symbol '$symbol_name' not found in $framework\n";
DynaLoader::dl_install_xsub("main::$function_name", $symbol);

eval {
  no strict "refs";
  &{"main::$function_name"}();
};
if ($@) {
  die "Error executing $function_name: $@\n";
}
