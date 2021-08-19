# Test Multi-Node TimeScale

Demonstrates defect with TimeScaleDB's multi-node native replication in the face of a single node failure where the failed node is later restored.

## Setup

* Docker with docker compose
* Image: timescale/timescaledb:2.4.0-pg13
* Single access node
* 3 data nodes
* 1 distributed hypertable with a replication factor of 3 and chunk_interval of 1 hour
* Inserts 59:59 worth of data for 50 different dev_ids into the table

## Test Case

* Check initial replication status and ability to select from the table
  * Expected: All chunks are replicated on all data nodes and SELECT succeeds
  * Actual: as expected
* Take down data node 3 (dn3, tsdb-data3), and test both SELECT and INSERT
  * Expected: SELECT succeeds but INSERT fails
  * Actual: Both SELECT and INSERT fail
* Detach and delete data node 3, and test SELECT
  * Expected: All chunks are replicated on dn1 and dn2 and SELECT succeeds
  * Actual: As expected
* Readd and reatach data node 3, and test SELECT
  * Expected: SELECT succeeds
  * Actual: As expected
* Rereplicate all chunks to data node 3, and test SELECT
  * Expected: All chunks are replicated on all data nodes and SELECT succeeds
  * Actual: As expected
* Take down data node 3, and test both SELECt and INSERT
  * Expected: SELECT and INSERT fail
  * Actual: SELECT succeeds but INSERT fails
  * In this case the expected is for both to fail because previously SELECT failed when the data node was down so it is reasonable to expect the same behavior after the node has been restored.
* Bring data node 3 backup and test SELECT
  * Expected: SELECT succeeds
  * Actual: As expected

See test.out for the output from my run of the test

## Running

```
./run-test.sh
```