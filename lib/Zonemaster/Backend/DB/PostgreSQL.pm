package Zonemaster::Backend::DB::PostgreSQL;

our $VERSION = '1.1.0';

use Moose;
use 5.14.2;

use DBI qw(:utils);
use Digest::MD5 qw(md5_hex);
use Encode;
use JSON::PP;
use Log::Any qw($log);

use Zonemaster::Backend::DB;

with 'Zonemaster::Backend::DB';

has 'host' => (
    is       => 'ro',
    isa      => 'Str',
);

has 'port' => (
    is       => 'ro',
    isa      => 'Int',
    required => 0,
);

has 'user' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'password' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'database' => (
    is       => 'ro',
    isa      => 'Str',
);

has 'dbhandle' => (
    is  => 'rw',
    isa => 'DBI::db',
);

sub from_config {
    my ( $class, $config ) = @_;

    return $class->new(    #
        host     => $config->POSTGRESQL_host,
        user     => $config->POSTGRESQL_user,
        password => $config->POSTGRESQL_password,
        database => $config->POSTGRESQL_database,
    );
}

sub dbh {
    my ( $self ) = @_;
    my $dbh = $self->dbhandle;

    if ( $dbh and $dbh->ping ) {
        return $dbh;
    }
    else {
        my $host     = $self->host;
        my $port     = $self->port;
        my $database = $self->database;

        my @dsn_params;
        if ( defined $self->host ) {
            push @dsn_params, "host=" . $self->host;
        }
        if ( defined $self->database ) {
            push @dsn_params, "database=" . $self->database;
        }
        my $data_source_name = 'DBI:Pg:' . join( ';', @dsn_params );

        $log->noticef( "Connecting to database: %s", $data_source_name );
        delete local $ENV{PGHOST};
        delete local $ENV{PGDATABASE};
        $dbh = DBI->connect(
            $data_source_name,
            $self->user,
            $self->password,
            {
                RaiseError => 1,
                AutoCommit => 1
            }
        );
        $dbh->{AutoInactiveDestroy} = 1;

        $self->dbhandle( $dbh );
        return $dbh;
    }
}

sub user_exists_in_db {
    my ( $self, $user ) = @_;

    my $dbh = $self->dbh;
    my ( $id ) = $dbh->selectrow_array( "SELECT id FROM users WHERE user_info->>'username'=?", undef, $user );

    return $id;
}

sub add_api_user_to_db {
    my ( $self, $user_name, $api_key ) = @_;

    my $dbh = $self->dbh;
    my $nb_inserted = $dbh->do( "INSERT INTO users (user_info) VALUES (?)", undef, encode_json( { username => $user_name, api_key => $api_key } ) );

    return $nb_inserted;
}

sub user_authorized {
    my ( $self, $user, $api_key ) = @_;

    my $dbh = $self->dbh;
    my $id =
      $dbh->selectrow_array( "SELECT id FROM users WHERE user_info->>'username'=? AND user_info->>'api_key'=?",
        undef, $user, $api_key );

    return $id;
}

sub test_progress {
    my ( $self, $test_id, $progress ) = @_;

    my $dbh = $self->dbh;
    if ( $progress ) {
        if ($progress == 1) {
            $dbh->do( "UPDATE test_results SET progress=?, test_start_time=NOW() WHERE hash_id=? AND progress <> 100", undef, $progress, $test_id );
        }
        else {
            $dbh->do( "UPDATE test_results SET progress=? WHERE hash_id=? AND progress <> 100", undef, $progress, $test_id );
        }
    }
    
    my ( $result ) = $dbh->selectrow_array( "SELECT progress FROM test_results WHERE hash_id=?", undef, $test_id );

    return $result;
}

sub create_new_batch_job {
    my ( $self, $username ) = @_;

    my $dbh = $self->dbh;
    my ( $batch_id, $creation_time ) = $dbh->selectrow_array( "
            SELECT 
                batch_id, 
                batch_jobs.creation_time AS batch_creation_time 
            FROM 
                test_results 
            JOIN batch_jobs 
                ON batch_id=batch_jobs.id 
                AND username=? WHERE 
                test_results.progress<>100
            LIMIT 1
            ", undef, $username );

    die "You can't create a new batch job, job:[$batch_id] started on:[$creation_time] still running \n" if ( $batch_id );

    my ( $new_batch_id ) =
      $dbh->selectrow_array( "INSERT INTO batch_jobs (username) VALUES (?) RETURNING id", undef, $username );

    return $new_batch_id;
}

sub create_new_test {
    my ( $self, $domain, $test_params, $seconds_between_tests_with_same_params, $batch_id ) = @_;
    my $dbh = $self->dbh;

    $test_params->{domain} = $domain;
    my $js = JSON::PP->new;
    $js->canonical( 1 );
    my $encoded_params                 = $js->encode( $test_params );
    my $test_params_deterministic_hash = md5_hex( encode_utf8( $encoded_params ) );

    my $priority = $test_params->{priority};
    my $queue = $test_params->{queue};

    my $sth = $dbh->prepare( "
        INSERT INTO test_results (batch_id, priority, queue, params_deterministic_hash, params)
        SELECT ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
            SELECT * FROM test_results
            WHERE params_deterministic_hash = ?
              AND creation_time > NOW() - ?::interval
        )" );
    my $nb_inserted = $sth->execute(    #
        $batch_id,
        $priority,
        $queue,
        $test_params_deterministic_hash,
        $encoded_params,
        $test_params_deterministic_hash,
        sprintf( "%d seconds", $seconds_between_tests_with_same_params ),
    );

    my ( undef, $hash_id ) = $dbh->selectrow_array(
        "SELECT id,hash_id FROM test_results WHERE params_deterministic_hash=? ORDER BY id DESC LIMIT 1", undef, $test_params_deterministic_hash );

    return $hash_id;
}

sub get_test_params {
    my ( $self, $test_id ) = @_;

    my $result;

    my $dbh = $self->dbh;
    my ( $params_json ) = $dbh->selectrow_array( "SELECT params FROM test_results WHERE hash_id=?", undef, $test_id );
    eval { $result = decode_json( encode_utf8( $params_json ) ); };
    die "$@ \n" if $@;

    return $result;
}

sub test_results {
    my ( $self, $test_id, $results ) = @_;

    my $dbh = $self->dbh;
    $dbh->do( "UPDATE test_results SET progress=100, test_end_time=NOW(), results = ? WHERE hash_id=? AND progress < 100",
        undef, $results, $test_id )
      if ( $results );

    my $result;
    eval {
        my ( $hrefs ) = $dbh->selectall_hashref( "SELECT id, hash_id, creation_time at time zone current_setting('TIMEZONE') at time zone 'UTC' as creation_time, params, results FROM test_results WHERE hash_id=?", 'hash_id', undef, $test_id );
        $result            = $hrefs->{$test_id};
        
        # This workaround is needed to properly handle all versions of perl and the DBD::Pg module 
        # More details in the zonemaster backend issue #570
        if (utf8::is_utf8($result->{params}) ) {
                $result->{params}  = decode_json( encode_utf8($result->{params}) );
        }
        else {
                $result->{params}  = decode_json( $result->{params} );
        }
        
        if (utf8::is_utf8($result->{results} ) ) {
                $result->{results}  = decode_json( encode_utf8($result->{results}) );
        }
        else {
                $result->{results}  = decode_json( $result->{results} );
        }
    };
    die "$@ \n" if $@;

    return $result;
}

sub get_test_history {
    my ( $self, $p ) = @_;

    my $dbh = $self->dbh;

    my $undelegated = "";
    if ($p->{filter} eq "undelegated") {
        $undelegated = "AND (params->'nameservers') IS NOT NULL";
    } elsif ($p->{filter} eq "delegated") {
        $undelegated = "AND (params->'nameservers') IS NULL";
    }

    my @results;
    my $query = "
        SELECT 
            (SELECT count(*) FROM (SELECT json_array_elements(results) AS result) AS t1 WHERE result->>'level'='CRITICAL') AS nb_critical,
            (SELECT count(*) FROM (SELECT json_array_elements(results) AS result) AS t1 WHERE result->>'level'='ERROR') AS nb_error,
            (SELECT count(*) FROM (SELECT json_array_elements(results) AS result) AS t1 WHERE result->>'level'='WARNING') AS nb_warning,
            id,
            hash_id,
            creation_time at time zone current_setting('TIMEZONE') at time zone 'UTC' as creation_time
        FROM test_results
        WHERE params->>'domain'=" . $dbh->quote( $p->{frontend_params}->{domain} ) . " $undelegated 
        ORDER BY id DESC 
        OFFSET $p->{offset} LIMIT $p->{limit}";
    my $sth1 = $dbh->prepare( $query );
    $sth1->execute;
    while ( my $h = $sth1->fetchrow_hashref ) {
        my $overall_result = 'ok';
        if ( $h->{nb_critical} ) {
            $overall_result = 'critical';
        }
        elsif ( $h->{nb_error} ) {
            $overall_result = 'error';
        }
        elsif ( $h->{nb_warning} ) {
            $overall_result = 'warning';
        }

        push(
            @results,
            {
                id               => $h->{hash_id},
                creation_time    => $h->{creation_time},
                overall_result   => $overall_result,
            }
        );
    }

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

        $dbh->begin_work();
        $dbh->do( "ALTER TABLE test_results DROP CONSTRAINT IF EXISTS test_results_pkey" );
        $dbh->do( "DROP INDEX IF EXISTS test_results__hash_id" );
        $dbh->do( "DROP INDEX IF EXISTS test_results__params_deterministic_hash" );
        $dbh->do( "DROP INDEX IF EXISTS test_results__batch_id_progress" );
        $dbh->do( "DROP INDEX IF EXISTS test_results__progress" );
        $dbh->do( "DROP INDEX IF EXISTS test_results__domain_undelegated" );
        
        $dbh->do( "COPY test_results(batch_id, priority, queue, params_deterministic_hash, params) FROM STDIN" );
        foreach my $domain ( @{$params->{domains}} ) {
            $test_params->{domain} = $domain;
            my $encoded_params                 = $js->encode( $test_params );
            my $test_params_deterministic_hash = md5_hex( encode_utf8( $encoded_params ) );

            $dbh->pg_putcopydata("$batch_id\t$priority\t$queue\t$test_params_deterministic_hash\t$encoded_params\n");
        }
        $dbh->pg_putcopyend();
        $dbh->do( "ALTER TABLE test_results ADD PRIMARY KEY (id)" );
        $dbh->do( "CREATE INDEX test_results__hash_id ON test_results (hash_id, creation_time)" );
        $dbh->do( "CREATE INDEX test_results__params_deterministic_hash ON test_results (params_deterministic_hash)" );
        $dbh->do( "CREATE INDEX test_results__batch_id_progress ON test_results (batch_id, progress)" );
        $dbh->do( "CREATE INDEX test_results__progress ON test_results (progress)" );
        $dbh->do( "CREATE INDEX test_results__domain_undelegated ON test_results ((params->>'domain'), (params->>'undelegated'))" );
        
        $dbh->commit();
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
            WHERE test_start_time < NOW() - ?::interval
            AND nb_retries <= ?
            AND progress > 0
            AND progress < 100
            AND queue = ?" );
        $sth->execute(    #
            sprintf( "%d seconds", $test_run_timeout ),
            $test_run_max_retries,
            $queue,
        );
        return $sth;
    }
    else {
        my $sth = $self->dbh->prepare( "
            SELECT hash_id, results, nb_retries
            FROM test_results
            WHERE test_start_time < NOW() - ?::interval
            AND nb_retries <= ?
            AND progress > 0
            AND progress < 100" );
        $sth->execute(    #
            sprintf( "%d seconds", $test_run_timeout ),
            $test_run_max_retries,
        );
        return $sth;
    }
}

sub process_unfinished_tests_give_up {
    my ( $self, $result, $hash_id ) = @_;

    $self->dbh->do("UPDATE test_results SET progress = 100, test_end_time = NOW(), results = ? WHERE hash_id=?", undef, encode_json($result), $hash_id);
}

sub schedule_for_retry {
    my ( $self, $hash_id ) = @_;

    $self->dbh->do("UPDATE test_results SET nb_retries = nb_retries + 1, progress = 0, test_start_time = NOW() WHERE hash_id=?", undef, $hash_id);
}

no Moose;
__PACKAGE__->meta()->make_immutable();

1;
