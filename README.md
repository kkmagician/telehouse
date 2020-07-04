# Telehouse
A small executable for sending Telegraf metrics to ClickHouse.<br>
Build with `dart2native bin/telehouse.dart -o telehouse` or with docker (see Dockerfile in the root).
Pull from DockerHub with `docker pull kkmagician/telehouse`

## How to use
### telegraf.conf
You can find a sample telegraf.conf file in the root. What to look at:
* Use the exec output type `[[outputs.exec]]`
* The command should start with `"./telehouse"` as it is the binary's name located in the workdir of Telegraf.
* Only JSON data format is supported at the moment `data_format = "json"`
* Timeout is up to you, it mostly depends on your connection to your ClickHouse's server. 

Available command flags:
* `-h` ClickHouse HTTP host with port if applicable. Default: `http://localhost:8123`
* `-u` ClickHouse user. Default: `default`
* `-p` ClickHouse password
* `-f` ClickHouse password file location if you use Docker Secrets
* `-t` ClickHouse table to write to. Default: `default.telehouse`
* `-q` Boolean flag of whether to check the values for single quotes or not. If your data may contain single quotes, use this flag. Default: `false` 

### ClickHouse configuration
#### Colums
All the metrics are sent to one table defined by the `-t` flag in your `telegraf.conf`. Those columns are expected in the target table:
* `name` the metric's name (String-like, e.g. String/FixedString/LowCardinality(String))
* `timestamp` UInt-like timestamp given by Telegraf. If your `telegraf.conf` uses second precision, you can use DateTime column datatype, otherwise it is recommended to go with UInt32/UInt64
* `tags` JSON string with tags
* `fields` JSON string with fields.

You may add any other columns like computed defaults (for example, date of insert).

#### Table engines
Sample table for storing all the metrics might look like this:
```SQL
CREATE TABLE default.telehouse (
    dt          Date DEFAULT today(),   -- current date for the partition key
    insert_time DateTime DEFAULT now(), -- insert time for debug purposes
    name        LowCardinality(String), -- metrics name
    tags        String,                 -- JSON tags
    fields      String,                 -- JSON fields
    timestamp   UInt64                  -- UNIX timestamp
) ENGINE = MergeTree() 
  PARTITION BY toYYYYMM(dt)
  ORDER BY (dt, name, insert_time, timestamp)
  TTL dt + 7
```

One of the options to extract distinct metric types into their own table may be with `MATERIALIZED VIEW`.
```SQL
CREATE MATERIALIZED VIEW default.docker
ENGINE = MergeTree() PARTITION BY toYYYYMM(dt) ORDER BY (dt, host, timestamp) 
AS
SELECT
    dt, timestamp,
    toDateTime(timestamp / 1000)                                  as timestamp_dt, -- divide by 1000 if you have ms precision
    JSONExtract(tags, 'host', 'LowCardinality(String)')           as host,
    JSONExtract(tags, 'server_version', 'LowCardinality(String)') as server_version,
    JSONExtract(fields, 'memory_total', 'UInt64')                 as memory_total,
    JSONExtract(fields, 'n_containers_running', 'UInt16')         as n_containers_running
FROM default.telehouse
WHERE name = 'docker'
```

If you don't want to store raw data from telehouse, you may use the [Null](https://clickhouse.tech/docs/en/engines/table-engines/special/null/) table engine but still extract specific data using views.

Depending on your ClickHouse layout, quantity of metrics and flush interval you might want to use Buffer table engine.