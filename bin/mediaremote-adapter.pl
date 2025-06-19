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
#   seek: Seeks to a specific timeline position
#
# PARAMS:
#   send(command)
#     command: The MRCommand ID as a number (e.g. kMRPlay = 0)
#   seek(position)
#     position: The timeline position in microseconds
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

sub fail {
  my ($error) = @_;
  print STDERR "$error\n";
  exit 1;
}

fail "Framework path not provided" unless @ARGV >= 1;

my $framework_path = shift @ARGV;
my $framework_basename = File::Basename::basename($framework_path);
fail "Provided path is not a framework: $framework_path"
  unless $framework_basename =~ s/\.framework$//;

my $framework = File::Spec->catfile($framework_path, $framework_basename);
fail "Framework not found at $framework" unless -e $framework;

my $handle = DynaLoader::dl_load_file($framework, 0)
  or fail "Failed to load framework: $framework";
my $function_name = shift @ARGV || "stream";
fail "Invalid function name: '$function_name'"
  unless $function_name eq "stream"
  || $function_name eq "get"
  || $function_name eq "send";

sub parse_options {
  my ($start_index) = @_;
  my %arg_map;
  my $i = $start_index;
  while ($i <= $#ARGV) {
    my $arg = $ARGV[$i];
    if ($arg =~ /^--([a-z\\-]+)(?:=(.*))?$/) {
      my $key = $1;
      my $value = defined $2 ? $2 : undef;
      $arg_map{$key} = $value;
      splice @ARGV, $i, 1;
    }
    else {
      $i++;
    }
  }
  return \%arg_map;
}

sub env_func {
  my $symbol_name = shift;
  return "${symbol_name}_env";
}

sub set_env_param {
  my ($func, $index, $name, $value) = @_;
  $ENV{"MEDIAREMOTEADAPTER_PARAM_${func}_${index}_${name}"} = "$value";
}

sub set_env_option_unsafe {
  my ($name, $value) = @_;
  $name =~ s/-/_/g;
  $ENV{"MEDIAREMOTEADAPTER_OPTION_${name}"} = defined $value ? "$value" : "";
}

sub set_env_option {
  my ($options, $key) = @_;
  my $value = $options->{$key};
  if (defined $value) {
    fail "Unexpected value for option '$key'";
  }
  set_env_option_unsafe($key, $value);
}

sub set_env_option_value {
  my ($options, $key) = @_;
  my $value = $options->{$key};
  if (!defined $value) {
    fail "Missing value for option '$key'";
  }
  set_env_option_unsafe($key, $value);
}

my $symbol_name = "adapter_$function_name";
if ($function_name eq "send") {
  my $id = shift @ARGV;
  fail "Missing ID for send command" unless defined $id;
  set_env_param($symbol_name, 0, "command", "$id");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "stream") {
  my $options = parse_options(0);
  foreach my $key (keys %{$options}) {
    if ($key eq "no-diff") {
      set_env_option($options, $key);
    }
    elsif ($key eq "debounce") {
      set_env_option_value($options, $key);
    }
    else {
      fail "Unrecognized option '$key'";
    }
  }
  $symbol_name = env_func($symbol_name);
}

if (defined shift @ARGV) {
  fail "Too many arguments";
}

my $symbol = DynaLoader::dl_find_symbol($handle, "$symbol_name")
  or fail "Symbol '$symbol_name' not found in $framework";
DynaLoader::dl_install_xsub("main::$function_name", $symbol);

eval {
  no strict "refs";
  &{"main::$function_name"}();
};
if ($@) {
  fail "Error executing $function_name: $@";
}
