#!/bin/bash

# Tests TimeScale's multi-node native replication feature in a simple failure scenario where one data node fails and is later restored
# The expectation is that when a data node is down transactions/commands that mutate data fail but SELECT will succeed as long as the data is available on other nodes
# The actual behavior is that even SELECTs will fail when the data node is down.
# AND once the data node is restored to service if it fails again SELECT's will succeed even when the data node is down.
# INSERTs do fail both prior to the data node being restored to service and after it is restored and subsequently fails

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Wait for Postgres to accept connections
pg_ready() {
  until psql -U postgres -h localhost -p $1 -c '\q' &> /dev/null; do
    sleep 1s
  done
}

# Get the replication status of all chunks
get_replication_status() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT * FROM timescaledb_experimental.chunk_replication_status;"
}

# Get the first 10 rows from the metric table
get_data() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT * FROM metric LIMIT 10;"
}

# Insert a new row into the metric table
insert_row() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "INSERT INTO metric (ts, val, dev_id) VALUES ('2021-08-17 00:00:00', 3.15, 51);"
}

# Use docker-compose to stop the given container
shutdown_node() {
  docker-compose stop $1
}

# Use docker compose to start the given container and wait for PG to be ready
start_node() {
  docker-compose start $1
  echo "Waiting for PG to be ready..."
  pg_ready $2
}

# Detach and then delete the given data node
# We delete because we can't simply reattach a data node that contains data
# and it is easier to just drop the database on the data node rather then attempt
# to bring it back into sync.
detach_node() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT detach_data_node('$1', force => true);"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT delete_data_node('$1', force => true);"
}

# Drop the database on the data node
# adding the data node will recreate the database
# attach the data node to the metric table
reattach_node() {
  psql -U postgres -h localhost -p $2 -c "DROP DATABASE testdb WITH(FORCE);"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT add_data_node('$1', host => 'tsdb-data3');"
  psql -U postgres -h localhost -p 5433 -d testdb -c "SELECT attach_data_node('$1', 'metric');"
}

# Manually copy the under replicated chunks back to the given data node from the given source
# We expect there to only be three chunks based on the setup and the way TimeScale names chunks
# This is done due to bugs with copy_chunk and procedures
rereplicate_chunks() {
  psql -U postgres -h localhost -p 5433 -d testdb -c "CALL timescaledb_experimental.copy_chunk('_timescaledb_internal._dist_hyper_1_1_chunk', '$1', '$2');"
  psql -U postgres -h localhost -p 5433 -d testdb -c "CALL timescaledb_experimental.copy_chunk('_timescaledb_internal._dist_hyper_1_2_chunk', '$1', '$2');"
  psql -U postgres -h localhost -p 5433 -d testdb -c "CALL timescaledb_experimental.copy_chunk('_timescaledb_internal._dist_hyper_1_3_chunk', '$1', '$2');"
}

# Color code output
print_info() {
  echo -e "${CYAN}"
  echo "$1"
  echo -e "${NC}"
}

print_success() {
  echo -e "${GREEN}"
  echo "$1"
  echo -e "${NC}"
}

print_fail() {
  echo -e "${RED}"
  echo "$1"
  echo -e "${NC}"
}

print_info "BEGIN TEST"

print_info "Bring up environment..."
docker-compose up -d

print_info "Wait for access node to be ready..."
pg_ready 5433

# Setup a distributed hypertable with a replication factor of 3
# This will mean all chunks are replicated to all data nodes
# Insert a bunch of data
print_info "Setting up database..."
psql -U postgres -h localhost -p 5433 -d testdb -f setup-test.sql
echo
print_info "Replication factor was set to 3 so all chunks should be on all data nodes."
get_replication_status
print_success "SELECT should be succesful."
get_data
print_info "Shutting down dn3 (tsdb-data3)..."
shutdown_node tsdb-data3
print_fail "SELECT fails due to dn3 being down, even with the data available on other data nodes."
get_data
print_success "INSERT fails due to dn3 being down as expected."
insert_row
print_info "Restart dn3 (tsdb-data3)..."
start_node tsdb-data3 5436
print_success "SELECT should succeed once more now that the data node is back online."
get_data
print_success "INSERT should succeed now that the data node is back online."
insert_row
print_info "Shutting down dn3 (tsdb-data3)..."
shutdown_node tsdb-data3
print_info "Forcefully detach and delete dn3 (tsdb-data3)..."
detach_node dn3
print_info "Replication status should show 2 nodes and all chunks are replicated on both nodes."
get_replication_status
print_success "SELECT should be successful this time since the failed node has been removed."
get_data
print_success "INSERT should be successful this time since the failed node has been removed."
insert_row
print_info "Restart dn3 (tsdb-data3)..."
start_node tsdb-data3 5436
print_info "Reattach and readd dn3 (tsdb-data3)..."
reattach_node dn3 5436
print_info "Replication satus should show 3 nodes and all chunks replicated to dn1 (tsdb-data1) and dn2 (tsdb-data2) but not dn3 (tsdb-data3)."
get_replication_status
print_success "SELECT should be successful since all data nodes are up."
get_data
print_success "INSERT should be successful since all data nodes are up."
insert_row
print_info "Shutting down dn3 (tsdb-data3)..."
shutdown_node tsdb-data3
print_success "SELECT should be successful since there are no chunks replicated to dn3 (tsdb-data3)."
get_data
print_success "INSERT should be successful since there are no chunks replicated to dn3 (tsdb-data3)."
insert_row
print_info "Restart dn3 (tsdb-data3)..."
start_node tsdb-data3 5436
print_info "Rereplicate all chunks to dn3 (tsdb-data3)..."
rereplicate_chunks dn1 dn3
print_info "Replication status should show 3 nodes and all chunks replicated to all 3 nodes."
get_replication_status
print_success "SELECT should be successful since all chunks are replicated to all nodes and all nodes are up."
get_data
print_success "INSERT should be successful since all chunks are replicated to all nodes and all nodes are up."
insert_row
print_info "Shutting down dn3 (tsdb-data3)..."
shutdown_node tsdb-data3
print_fail "SELECT should fail since dn3 is shutdown and contains a replica of each chunk."
get_data
echo -e "${RED}"
echo -e "!!!DEFECT!!!"
echo -e "EXPECTED: SELECT should have failed since dn3 is shutdown and it is attached to metric table and contains a replica of each chunk!"
echo -e "ACTUAL: SELECT succeeds!"
echo -e "!!!DEFECT!!!"
echo -e "${NC}"
print_success "INSERT fails because dn3 is down as expected."
insert_row
print_info "Restart dn3 (tsdb-data3)..."
start_node tsdb-data3 5436
print_success "SELECT should be successful since all chunks are replicated to all nodes and all nodes are up."
get_data

print_info "Tear down environment..."
docker-compose down -v
print_info "END TEST"
