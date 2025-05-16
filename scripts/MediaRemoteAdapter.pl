use strict;
use warnings;
use DynaLoader;
use File::Spec;

die "Framework path not provided" unless @ARGV == 1;

my $framework_path = $ARGV[0];
my $framework = File::Spec->catfile( $framework_path, 'MediaRemoteAdapter' );
die "Framework not found at $framework\n" unless -e $framework;

my $handle = DynaLoader::dl_load_file( $framework, 0 )
  or die "Failed to load framework: $framework\n";
my $symbol = DynaLoader::dl_find_symbol( $handle, 'loop' )
  or die "Symbol 'loop' not found in $framework\n";
DynaLoader::dl_install_xsub( 'main::loop', $symbol );

loop();
