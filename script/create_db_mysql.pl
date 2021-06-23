use strict;
use warnings;
use utf8;
use Data::Dumper;
use Encode;

use DBI qw(:utils);

use Zonemaster::Backend::Config;
use Zonemaster::Backend::DB::MySQL;

my $config = Zonemaster::Backend::Config->load_config();
if ( $config->DB_engine ne 'MySQL' ) {
    die "The configuration file does not contain the MySQL backend";
}
my $dbh = Zonemaster::Backend::DB::MySQL->from_config( $config )->dbh;

sub create_db {

    ####################################################################
    # TEST RESULTS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS test_specs CASCADE' );

    $dbh->do( 'DROP TABLE IF EXISTS test_results CASCADE' );

    $dbh->do(
        'CREATE TABLE test_results (
            id integer AUTO_INCREMENT PRIMARY KEY,
            hash_id VARCHAR(16) DEFAULT NULL,
            domain varchar(255) NOT NULL,
            batch_id integer NULL,
            creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
            test_start_time TIMESTAMP NULL DEFAULT NULL,
            test_end_time TIMESTAMP NULL DEFAULT NULL,
            priority integer DEFAULT 10,
            queue integer DEFAULT 0,
            progress integer DEFAULT 0,
            params_deterministic_hash character varying(32),
            params blob NOT NULL,
            results blob DEFAULT NULL,
            undelegated boolean NOT NULL DEFAULT false,
            nb_retries integer NOT NULL DEFAULT 0
        ) ENGINE=InnoDB
        '
    );
    
    $dbh->do(
        'CREATE TRIGGER before_insert_test_results
            BEFORE INSERT ON test_results
            FOR EACH ROW
            BEGIN
                IF new.hash_id IS NULL OR new.hash_id=\'\'
                THEN
                    SET new.hash_id = SUBSTRING(MD5(CONCAT(RAND(), UUID())) from 1 for 16);
                END IF;
            END;
        '
    );

    $dbh->do(
        'CREATE INDEX test_results__hash_id ON test_results (hash_id)'
    );
    
    $dbh->do(
        'CREATE INDEX test_results__params_deterministic_hash ON test_results (params_deterministic_hash)'
    );

    $dbh->do(
        'CREATE INDEX test_results__batch_id_progress ON test_results (batch_id, progress)'
    );
    
    $dbh->do( "CREATE INDEX test_results__domain_undelegated ON test_results (domain, undelegated)" );
    
    ####################################################################
    # BATCH JOBS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS batch_jobs CASCADE' );

    $dbh->do(
        'CREATE TABLE batch_jobs (
            id integer AUTO_INCREMENT PRIMARY KEY,
            username character varying(50) NOT NULL,
            creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
        ) ENGINE=InnoDB;
        '
    );

    ####################################################################
    # USERS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS users CASCADE' );

    $dbh->do(
        'CREATE TABLE users (
            id integer AUTO_INCREMENT primary key,
            username varchar(128),
            api_key varchar(512),
            user_info blob DEFAULT NULL
        ) ENGINE=InnoDB;
        '
    );
}

create_db();
