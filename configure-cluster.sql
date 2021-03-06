-- Ensure TimeScale is enabled
-- Connect access node to data nodes
CREATE EXTENSION IF NOT EXISTS timescaledb;
SELECT add_data_node('dn1', host => 'tsdb-data1');
SELECT add_data_node('dn2', host => 'tsdb-data2');
SELECT add_data_node('dn3', host => 'tsdb-data3');