use strict;
use warnings;
use 5.14.2;

use Test::More;    # see done_testing()
use Test::Exception;
use Zonemaster::Engine;
use JSON::PP;
use File::ShareDir qw[dist_file];

# Use the TARGET environment variable to set the database to use
# default to SQLite
my $db_backend = $ENV{TARGET};
if ( not $db_backend ) {
    $db_backend = 'SQLite';
} elsif ( $db_backend !~ /^(?:SQLite|MySQL|PostgreSQL)$/ ) {
    BAIL_OUT( "Unsupported database backend: $db_backend" );
}

diag "database: $db_backend";

my $datafile = q{t/test01.data};
if ( not $ENV{ZONEMASTER_RECORD} ) {
    die q{Stored data file missing} if not -r $datafile;
    Zonemaster::Engine->preload_cache( $datafile );
    Zonemaster::Engine->profile->set( q{no_network}, 1 );
    diag "not recording";
} else {
    diag "recording";
}

# The configuration file should be the default
# configuration file, unless the ENV variable below is already
# set (e.g. for Travis). Set the ENV variable, and this must
# be done before Zonemaster::Backend::Config is loaded.
unless ($ENV{ZONEMASTER_BACKEND_CONFIG_FILE}) {
       $ENV{ZONEMASTER_BACKEND_CONFIG_FILE} =
       dist_file('Zonemaster-Backend', "backend_config.ini");
};

# Require Zonemaster::Backend::RPCAPI.pm test
use_ok( 'Zonemaster::Backend::RPCAPI' );

use_ok( 'Zonemaster::Backend::Config' );
my $config = Zonemaster::Backend::Config->load_config();

# Create Zonemaster::Backend::RPCAPI object
my $engine = Zonemaster::Backend::RPCAPI->new(
    {
        dbtype => $db_backend,
        config => $config,
    }
);
isa_ok( $engine, 'Zonemaster::Backend::RPCAPI' );

if ( $db_backend eq 'SQLite' ) {
    # create a new memory SQLite database
    ok( $engine->{db}->create_db(), "$db_backend database created");
}

# add test user
is( $engine->add_api_user( { username => "zonemaster_test", api_key => "zonemaster_test's api key" } ), 1, 'API add_api_user success');

my $user_check_query;
if ( $db_backend eq 'PostgreSQL' ) {
    $user_check_query = q/SELECT * FROM users WHERE user_info->>'username' = 'zonemaster_test'/;
}
elsif ( $db_backend eq 'MySQL' || $db_backend eq 'SQLite' ) {
    $user_check_query = q/SELECT * FROM users WHERE username = 'zonemaster_test'/;
}
is( scalar( $engine->{db}->dbh->selectrow_array( $user_check_query ) ), 1 ,'API add_api_user user created' );

# add a new test to the db
my $frontend_params_1 = {
    client_id      => 'Unit Test',         # free string
    client_version => '1.0',               # free version like string
    domain         => 'afnic.fr',          # content of the domain text field
    ipv4           => JSON::PP::true,                   # 0 or 1, is the ipv4 checkbox checked
    ipv6           => JSON::PP::true,                   # 0 or 1, is the ipv6 checkbox checked
    profile        => 'default',    # the id if the Test profile listbox

    nameservers => [                       # list of the nameserves up to 32
        { ns => 'ns1.nic.fr' },       # key values pairs representing nameserver => namesterver_ip
        { ns => 'ns2.nic.fr', ip => '192.134.4.1' },
    ],
    ds_info => [                                  # list of DS/Digest pairs up to 32
        { keytag => 11627, algorithm => 8, digtype => 2, digest => 'a6cca9e6027ecc80ba0f6d747923127f1d69005fe4f0ec0461bd633482595448' },
    ],
};

sub run_zonemaster_test_with_backend_API {
    my ($test_id) = @_;

    my $hash_id = $engine->start_domain_test( $frontend_params_1 );
    ok( $hash_id, "API start_domain_test OK" );
    is( length($hash_id), 16, "Test has a 16 characters length hash ID (hash_id=$hash_id)" );
    is( scalar( $engine->{db}->dbh->selectrow_array( qq/SELECT id FROM test_results WHERE id=$test_id/ ) ), $test_id , 'API start_domain_test -> Test inserted in the DB' );

    # test test_progress API
    is( $engine->test_progress( { test_id => $hash_id } ), 0 , 'API test_progress -> OK');

    if ( not $ENV{ZONEMASTER_RECORD} ) {
        Zonemaster::Engine->preload_cache( $datafile );
        Zonemaster::Engine->profile->set( q{no_network}, 1 );
    }

    use_ok( 'Zonemaster::Backend::TestAgent' );
    my $agent = Zonemaster::Backend::TestAgent->new( { dbtype => "$db_backend", config => $config } );
    isa_ok($agent, 'Zonemaster::Backend::TestAgent', 'agent');

    diag "running the agent on test $hash_id";
    $agent->run( $hash_id );

    Zonemaster::Backend::TestAgent->reset() unless ( $ENV{ZONEMASTER_RECORD} );

    is( $engine->test_progress( { test_id => $hash_id } ), 100 , 'API test_progress -> Test finished' );

    my $test_results = $engine->get_test_results( { id => $hash_id, language => 'fr_FR' } );
    ok( defined $test_results->{id},                 'TEST1 $test_results->{id} defined' );
    ok( defined $test_results->{params},             'TEST1 $test_results->{params} defined' );
    ok( defined $test_results->{creation_time},      'TEST1 $test_results->{creation_time} defined' );
    ok( defined $test_results->{results},            'TEST1 $test_results->{results} defined' );
    cmp_ok( scalar( @{ $test_results->{results} } ), '>', 1, 'TEST1 got some results' );

    dies_ok { $engine->get_test_results( { id => $hash_id, language => 'fr-FR' } ); }
    'API get_test_results -> [results] parameter not present (wrong language tag: underscore not hyphen)'; # Should be underscore, not hyphen.

    dies_ok { $engine->get_test_results( { id => $hash_id, language => 'zz' } ); }
    'API get_test_results -> [results] parameter not present (wrong language tag: "zz" unknown)'; # "zz" is not our configuration file.
}

run_zonemaster_test_with_backend_API(1);
$frontend_params_1->{ipv6} = 0;
run_zonemaster_test_with_backend_API(2);

my $offset = 0;
my $limit  = 10;
my $test_history =
    $engine->get_test_history( { frontend_params => $frontend_params_1, offset => $offset, limit => $limit } );
diag explain( $test_history );
is( scalar( @$test_history ), 2, 'Two tests created' );

is( length($test_history->[0]->{id}), 16, 'Test 0 has 16 characters length hash ID' );
is( length($test_history->[1]->{id}), 16, 'Test 1 has 16 characters length hash ID' );

if ( $ENV{ZONEMASTER_RECORD} ) {
    Zonemaster::Engine->save_cache( $datafile );
}

done_testing();

if ( $db_backend eq 'SQLite' ) {
    my $dbfile = $engine->{db}->dbh->sqlite_db_filename;
    if ( -e $dbfile and -M $dbfile < 0 and -o $dbfile ) {
        unlink $dbfile;
    }
}
