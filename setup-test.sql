-- Create a basic hypertable
CREATE TABLE metric (ts TIMESTAMPTZ NOT NULL, val FLOAT8 NOT NULL, dev_id INT4 NOT NULL);
SELECT create_distributed_hypertable('metric', 'ts', 'dev_id', chunk_time_interval => INTERVAL '1 hour', replication_factor => 3);

-- Insert some data to generate chunks
INSERT INTO metric (ts, val, dev_id) SELECT s.*, 3.14+1, d.* FROM generate_series('2021-08-17 00:00:00'::timestamp, '2021-08-17 00:59:59'::timestamp, '1 s'::interval) s CROSS JOIN generate_series(1, 50) d;
