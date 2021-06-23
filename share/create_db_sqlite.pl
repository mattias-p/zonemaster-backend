use strict;
use warnings;
use utf8;
use Data::Dumper;
use Encode;

use DBI qw(:utils);

use Zonemaster::Backend::Config;
use Zonemaster::Backend::DB::SQLite;

my $config = Zonemaster::Backend::Config->load_config();
if ( $config->DB_engine ne 'SQLite' ) {
    die "The configuration file does not contain the SQLite backend";
}
my $db = Zonemaster::Backend::DB::SQLite->from_config( $config );
$db->cleanup_schema();
$db->init_schema();
