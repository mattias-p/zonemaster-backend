package Zonemaster::Backend::DB::SQLite;

our $VERSION = '1.1.0';

use Moose;
use 5.14.2;

use Data::Dumper;
use DBI qw(:utils);
use Digest::MD5 qw(md5_hex);
use Encode;
use JSON::PP;
use Log::Any qw( $log );

with 'Zonemaster::Backend::DB';

has 'database_file' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'dbh' => (
    is  => 'rw',
    isa => 'DBI::db',
);

sub from_config {
    my ( $class, $config ) = @_;

    return $class->new( database_file => $config->SQLITE_database_file );
}

sub BUILD {
    my ( $self ) = @_;

    if ( !defined $self->dbh ) {
        my $file = $self->database_file;

        $log->notice( "Opening SQLite: file=$file" ) if $log->is_notice;
        my $dbh = DBI->connect(
            "DBI:SQLite:dbname=$file",
            undef, undef,
            {
                AutoCommit => 1,
                RaiseError => 1,
            }
        );

        $self->dbh( $dbh );
    }

    return $self;
}

sub DEMOLISH {
    my ( $self ) = @_;
    $self->dbh->disconnect() if $self->dbh;
}

=head2 init_db

Create database and user.

=cut

sub init_db {
    return;
}

=head2 cleanup_db

Drop database and user.

=cut

sub cleanup_db {
    return;
}

=head2 init_schema

Defined database schema.

Consists of things like tables, indices and triggers.

=cut

sub init_schema {
    my ( $self ) = @_;

    $self->dbh->do(
        q{
            CREATE TABLE test_results (
                id integer PRIMARY KEY AUTOINCREMENT,
                hash_id VARCHAR(16) DEFAULT NULL,
                domain VARCHAR(255) NOT NULL,
                batch_id integer NULL,
                creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
                test_start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
                test_end_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
                priority integer DEFAULT 10,
                queue integer DEFAULT 0,
                progress integer DEFAULT 0,
                params_deterministic_hash character varying(32),
                params text NOT NULL,
                results text DEFAULT NULL,
                undelegated boolean NOT NULL DEFAULT false,
                nb_retries integer NOT NULL DEFAULT 0
            )
        }
    );

    $self->dbh->do(
        'CREATE TABLE batch_jobs (
                         id integer PRIMARY KEY,
                         username character varying(50) NOT NULL,
                         creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
               )
     '
    );

    $self->dbh->do(
        'CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username varchar(128),
                    api_key varchar(512),
                    user_info json DEFAULT NULL
               )
     '
    );
}

=head2 cleanup_schema

Drop tables and indices.

=cut

sub cleanup_schema {
    my ( $self ) = @_;

    $self->dbh->do( 'DROP TABLE IF EXISTS users' );
    $self->dbh->do( 'DROP TABLE IF EXISTS batch_jobs' );
    $self->dbh->do( 'DROP TABLE IF EXISTS test_results' );

    return;
}

sub user_exists_in_db {
    my ( $self, $user ) = @_;

    my ( $id ) = $self->dbh->selectrow_array( "SELECT id FROM users WHERE username = ?", undef, $user );

    return $id;
}

sub add_api_user_to_db {
    my ( $self, $user_name, $api_key  ) = @_;

    my $nb_inserted = $self->dbh->do(
        "INSERT INTO users (user_info, username, api_key) VALUES (?,?,?)",
        undef,
        'NULL',
        $user_name,
        $api_key,
    );

    return $nb_inserted;
}

sub user_authorized {
    my ( $self, $user, $api_key ) = @_;

    my ( $id ) =
      $self->dbh->selectrow_array( q[SELECT id FROM users WHERE username = ? AND api_key = ?], undef, $user, $api_key );
      
    return $id;
}

sub create_new_batch_job {
    my ( $self, $username ) = @_;

    my ( $batch_id, $creaton_time ) = $self->dbh->selectrow_array( "
               SELECT 
                    batch_id, 
                    batch_jobs.creation_time AS batch_creation_time 
               FROM 
                    test_results 
               JOIN batch_jobs 
                    ON batch_id=batch_jobs.id 
                    AND username=" . $self->dbh->quote( $username ) . " WHERE 
                    test_results.progress<>100
               LIMIT 1
               " );

    die "You can't create a new batch job, job:[$batch_id] started on:[$creaton_time] still running \n" if ( $batch_id );

    $self->dbh->do("INSERT INTO batch_jobs (username) VALUES(" . $self->dbh->quote( $username ) . ")" );
    my ( $new_batch_id ) = $self->dbh->sqlite_last_insert_rowid;

    return $new_batch_id;
}

sub create_new_test {
    my ( $self, $domain, $test_params, $seconds, $batch_id ) = @_;

    my $dbh = $self->dbh;

    $test_params->{domain} = $domain;
    my $js                             = JSON::PP->new->canonical;
    my $encoded_params                 = $js->encode( $test_params );
    my $test_params_deterministic_hash = md5_hex( $encoded_params );
    my $result_id;

    my $priority = $test_params->{priority};
    my $queue = $test_params->{queue};

    # Search for recent test result with the test same parameters, where "$seconds"
    # gives the time limit for how old test result that is accepted.
    my ( $recent_hash_id ) = $dbh->selectrow_array(
        "SELECT hash_id FROM test_results WHERE params_deterministic_hash = ? AND test_start_time > DATETIME('now', ?)",
        undef,
        $test_params_deterministic_hash,
        "-$seconds seconds"
    );

    if ( $recent_hash_id ) {
        # A recent entry exists, so return its id
        $result_id = $recent_hash_id;
    }
    else {

        # The SQLite database engine does not have support to create the "hash_id" by a
        # database engine trigger. "hash_id" is assumed to hold a unique hash. Uniqueness
        # cannot, however, be guaranteed. Same as with the other database engines.
        my $hash_id = substr(md5_hex(time().rand()), 0, 16);

        my $fields = 'hash_id, batch_id, priority, queue, params_deterministic_hash, params, domain, test_start_time, undelegated';
        $dbh->do(
            "INSERT INTO test_results ($fields) VALUES (?,?,?,?,?,?,?, datetime('now'),?)",
            undef,
            $hash_id,
            $batch_id,
            $priority,
            $queue,
            $test_params_deterministic_hash,
            $encoded_params,
            $test_params->{domain},
            ($test_params->{nameservers})?(1):(0),
        );
        $result_id = $hash_id;
    }

    return $result_id; # Return test ID, either test previously run or just created.
}

sub test_progress {
    my ( $self, $test_id, $progress ) = @_;

    my $dbh = $self->dbh;
    if ( $progress ) {
        if ($progress == 1) {
            $dbh->do( "UPDATE test_results SET progress=?, test_start_time=datetime('now') WHERE hash_id=? AND progress <> 100", undef, $progress, $test_id );
        }
        else {
            $dbh->do( "UPDATE test_results SET progress=? WHERE hash_id=? AND progress <> 100", undef, $progress, $test_id );
        }
    }

    my ( $result ) = $self->dbh->selectrow_array( "SELECT progress FROM test_results WHERE hash_id=?", undef, $test_id );

    return $result;
}

sub get_test_params {
    my ( $self, $test_id ) = @_;

    my ( $params_json ) = $self->dbh->selectrow_array( "SELECT params FROM test_results WHERE hash_id=?", undef, $test_id );

    my $result;
    eval {
        $result = decode_json( $params_json );
    };
    
    $log->warn( "decoding of params_json failed (test_id: [$test_id]):".Dumper($params_json) ) if $@;

    return $result;
}

sub test_results {
    my ( $self, $test_id, $new_results ) = @_;

    if ( $new_results ) {
        $self->dbh->do( qq[UPDATE test_results SET progress=100, test_end_time=datetime('now'), results = ? WHERE hash_id=? AND progress < 100],
            undef, $new_results, $test_id );
    }

    my $result;
    my ( $hrefs ) = $self->dbh->selectall_hashref( "SELECT id, hash_id, creation_time, params, results FROM test_results WHERE hash_id=?", 'hash_id', undef, $test_id );
    $result            = $hrefs->{$test_id};
    $result->{params}  = decode_json( $result->{params} );
    $result->{results} = decode_json( $result->{results} );

    return $result;
}

sub get_test_history {
    my ( $self, $p ) = @_;

    my @results;

    my $undelegated = "";
    if ($p->{filter} eq "undelegated") {
        $undelegated = "AND (params->'nameservers') IS NOT NULL";
    } elsif ($p->{filter} eq "delegated") {
        $undelegated = "AND (params->'nameservers') IS NULL";
    }

    my $quoted_domain = $self->dbh->quote( $p->{frontend_params}->{domain} );
    $quoted_domain =~ s/'/"/g;
    my $query = "SELECT
                    id,
                    hash_id,
                    creation_time,
                    params,
                    results   
                 FROM
                    test_results
                 WHERE
                    params like '\%\"domain\":$quoted_domain\%'
                    $undelegated
                 ORDER BY id DESC LIMIT $p->{limit} OFFSET $p->{offset} ";
    my $sth1 = $self->dbh->prepare( $query );
    $sth1->execute;
    while ( my $h = $sth1->fetchrow_hashref ) {
        $h->{results} = decode_json($h->{results}) if $h->{results};
        my $critical = ( grep { $_->{level} eq 'CRITICAL' } @{ $h->{results} } );
        my $error    = ( grep { $_->{level} eq 'ERROR' } @{ $h->{results} } );
        my $warning  = ( grep { $_->{level} eq 'WARNING' } @{ $h->{results} } );

        # More important overwrites
        my $overall = 'INFO';
        $overall = 'warning'  if $warning;
        $overall = 'error'    if $error;
        $overall = 'critical' if $critical;
        push( @results,
              {
                  id => $h->{hash_id},
                  creation_time => $h->{creation_time},
                  overall_result   => $overall,
              }
            );
    }
    $sth1->finish;

    return \@results;
}

sub add_batch_job {
    my ( $self, $params ) = @_;
    my $batch_id;

    my $dbh = $self->dbh;
    my $js = JSON::PP->new;
    $js->canonical( 1 );

    if ( $self->user_authorized( $params->{username}, $params->{api_key} ) ) {
        $batch_id = $self->create_new_batch_job( $params->{username} );

        my $test_params = $params->{test_params};
        my $priority = $test_params->{priority};
        my $queue = $test_params->{queue};

        $dbh->{AutoCommit} = 0;
        eval {$dbh->do( "DROP INDEX IF EXISTS test_results__hash_id " );};
        eval {$dbh->do( "DROP INDEX IF EXISTS test_results__params_deterministic_hash " );};
        eval {$dbh->do( "DROP INDEX IF EXISTS test_results__batch_id_progress " );};
        eval {$dbh->do( "DROP INDEX IF EXISTS test_results__progress " );};
        eval {$dbh->do( "DROP INDEX IF EXISTS test_results__domain_undelegated " );};
        
        my $sth = $dbh->prepare( 'INSERT INTO test_results (hash_id, domain, batch_id, priority, queue, params_deterministic_hash, params) VALUES (?, ?, ?, ?, ?, ?, ?) ' );
        foreach my $domain ( @{$params->{domains}} ) {
            $test_params->{domain} = $domain;
            my $encoded_params                 = $js->encode( $test_params );
            my $test_params_deterministic_hash = md5_hex( encode_utf8( $encoded_params ) );

            $sth->execute( substr(md5_hex(time().rand()), 0, 16), $test_params->{domain}, $batch_id, $priority, $queue, $test_params_deterministic_hash, $encoded_params );
        }
        $dbh->do( "CREATE INDEX test_results__hash_id ON test_results (hash_id, creation_time)" );
        $dbh->do( "CREATE INDEX test_results__params_deterministic_hash ON test_results (params_deterministic_hash)" );
        $dbh->do( "CREATE INDEX test_results__batch_id_progress ON test_results (batch_id, progress)" );
        $dbh->do( "CREATE INDEX test_results__progress ON test_results (progress)" );
        $dbh->do( "CREATE INDEX test_results__domain_undelegated ON test_results (domain, undelegated)" );
       
        $dbh->commit();
        $dbh->{AutoCommit} = 1;
    }
    else {
        die "User $params->{username} not authorized to use batch mode\n";
    }

    return $batch_id;
}

sub select_unfinished_tests {
    my ( $self, $queue, $test_run_timeout, $test_run_max_retries ) = @_;

    if ( $queue ) {
        my $sth = $self->dbh->prepare( "
            SELECT hash_id, results, nb_retries
            FROM test_results
            WHERE test_start_time < DATETIME('now', ?)
            AND nb_retries <= ?
            AND progress > 0
            AND progress < 100
            AND queue = ?" );
        $sth->execute(    #
            sprintf( "-%d seconds", $test_run_timeout ),
            $test_run_max_retries,
            $queue,
        );
        return $sth;
    }
    else {
        my $sth = $self->dbh->prepare( "
            SELECT hash_id, results, nb_retries
            FROM test_results
            WHERE test_start_time < DATETIME('now', ?)
            AND nb_retries <= ?
            AND progress > 0
            AND progress < 100" );
        $sth->execute(    #
            sprintf( "-%d seconds", $test_run_timeout ),
            $test_run_max_retries,
        );
        return $sth;
    }
}

sub process_unfinished_tests_give_up {
     my ( $self, $result, $hash_id ) = @_;

     $self->dbh->do("UPDATE test_results SET progress = 100, test_end_time = DATETIME('now'), results = ? WHERE hash_id=?", undef, encode_json($result), $hash_id);
}

sub schedule_for_retry {
    my ( $self, $hash_id ) = @_;

    $self->dbh->do("UPDATE test_results SET nb_retries = nb_retries + 1, progress = 0, test_start_time = DATETIME('now') WHERE hash_id=?", undef, $hash_id);
}

no Moose;
__PACKAGE__->meta()->make_immutable();

1;
