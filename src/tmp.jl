# This here are either because they don't have a place yet, or are necessary to help in the refactor

function _append_given_durations(appender, row, durations)
    s = 1
    for Δ in durations
        e = s + Δ - 1
        if haskey(row, :asset)
            DuckDB.append(appender, row.asset)
        else
            DuckDB.append(appender, row.from_asset)
            DuckDB.append(appender, row.to_asset)
        end
        DuckDB.append(appender, row.year)
        DuckDB.append(appender, row.rep_period)
        if haskey(row, :efficiency)
            DuckDB.append(appender, row.efficiency)
        end
        DuckDB.append(appender, s)
        DuckDB.append(appender, e)
        DuckDB.end_row(appender)
        s = e + 1
    end
    return
end

"""
    tmp_create_partition_tables(connection)

Create the unrolled partition tables using only tables.

The table `explicit_assets_rep_periods_partitions` is the explicit version of
`assets_rep_periods_partitions`, i.e., it adds the rows not defined in that
table by setting the specification to 'uniform' and the partition to '1'.

The table `asset_time_resolution` is the unrolled version of the table above,
i.e., it takes the specification and partition and expands into a series of
time blocks. The columns `time_block_start` and `time_block_end` replace the
`specification` and `partition` columns.

Similarly, `flow` tables are created as well.
"""
function tmp_create_partition_tables(connection)
    # DISTINCT is required because without commission year, it can be repeated
    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE explicit_assets_rep_periods_partitions AS
        SELECT DISTINCT
            t_assets.name AS asset,
            t_assets.year AS year,
            t_rp.rep_period AS rep_period,
            COALESCE(t_partition.specification, 'uniform') AS specification,
            COALESCE(t_partition.partition, '1') AS partition,
            t_rp.num_timesteps,
        FROM assets_data AS t_assets
        LEFT JOIN rep_periods_data as t_rp
            ON t_rp.year=t_assets.year
        LEFT JOIN assets_rep_periods_partitions as t_partition
            ON t_assets.name=t_partition.asset
                AND t_rp.rep_period=t_partition.rep_period
        WHERE t_assets.active=true
        ORDER BY year, rep_period
        ",
    )

    # TODO: Bug: If you don't set t_rp.rep_period=t_partition.rep_period, then
    # it creates at least one wrong entry with a wrong rep_period.
    # If you set it, then many entries are missing because t_partition.rep_period is not always defined
    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE explicit_flows_rep_periods_partitions AS
        SELECT DISTINCT
            t_flows.from_asset,
            t_flows.to_asset,
            t_flows.year AS year,
            t_rp.rep_period AS rep_period,
            COALESCE(t_partition.specification, 'uniform') AS specification,
            COALESCE(t_partition.partition, '1') AS partition,
            t_flows.efficiency,
            t_rp.num_timesteps,
        FROM flows_data AS t_flows
        LEFT JOIN rep_periods_data as t_rp
            ON t_rp.year=t_flows.year
        LEFT JOIN flows_rep_periods_partitions as t_partition
            ON t_flows.from_asset=t_partition.from_asset
                AND t_flows.to_asset=t_partition.to_asset
                AND t_rp.rep_period=t_partition.rep_period
        WHERE t_flows.active=true
        ORDER BY year, rep_period
        ",
    )

    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE asset_time_resolution(
            asset STRING,
            year INT,
            rep_period INT,
            time_block_start INT,
            time_block_end INT
        )",
    )

    appender = DuckDB.Appender(connection, "asset_time_resolution")
    for row in TulipaIO.get_table(Val(:raw), connection, "explicit_assets_rep_periods_partitions")
        durations = if row.specification == "uniform"
            step = parse(Int, row.partition)
            durations = Iterators.repeated(step, div(row.num_timesteps, step))
        elseif row.specification == "explicit"
            durations = parse.(Int, split(row.partition, ";"))
        elseif row.specification == "math"
            atoms = split(row.partition, "+")
            durations =
                (
                    begin
                        r, d = parse.(Int, split(atom, "x"))
                        Iterators.repeated(d, r)
                    end for atom in atoms
                ) |> Iterators.flatten
        else
            error("Row specification '$(row.specification)' is not valid")
        end
        _append_given_durations(appender, row, durations)
    end
    DuckDB.close(appender)

    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE flow_time_resolution(
            from_asset STRING,
            to_asset STRING,
            year INT,
            rep_period INT,
            efficiency DOUBLE,
            time_block_start INT,
            time_block_end INT
        )",
    )

    appender = DuckDB.Appender(connection, "flow_time_resolution")
    for row in TulipaIO.get_table(Val(:raw), connection, "explicit_flows_rep_periods_partitions")
        durations = if row.specification == "uniform"
            step = parse(Int, row.partition)
            durations = Iterators.repeated(step, div(row.num_timesteps, step))
        elseif row.specification == "explicit"
            durations = parse.(Int, split(row.partition, ";"))
        elseif row.specification == "math"
            atoms = split(row.partition, "+")
            durations =
                (
                    begin
                        r, d = parse.(Int, split(atom, "x"))
                        Iterators.repeated(d, r)
                    end for atom in atoms
                ) |> Iterators.flatten
        else
            error("Row specification '$(row.specification)' is not valid")
        end
        _append_given_durations(appender, row, durations)
    end
    DuckDB.close(appender)
end

function tmp_create_constraints_indexes(connection)
    # Create a list of all (asset, year, rp) and also data used in filtering
    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE t_cons_indexes AS
        SELECT DISTINCT
            assets_data.name as asset,
            assets_data.year,
            rep_periods_data.rep_period,
            graph_assets_data.type,
            rep_periods_data.num_timesteps,
            assets_data.unit_commitment,
        FROM assets_data
        LEFT JOIN graph_assets_data
            ON assets_data.name=graph_assets_data.name
        LEFT JOIN rep_periods_data
            ON assets_data.year=rep_periods_data.year
        WHERE assets_data.active=true
        ORDER BY assets_data.year,rep_periods_data.rep_period
        ",
    )

    #= Replacing the following example:
        (
            name = :highest_in_out,
            partitions = _allflows,
            strategy = :highest,
            asset_filter = (a, y) -> graph[a].type in ["hub", "consumer"],
        ),
    =#
    DBInterface.execute(
        connection,
        "CREATE OR REPLACE TABLE cons_indexes_highest_in_out(
            asset STRING,
            year INT,
            rep_period INT,
            time_block_start INT,
            time_block_end INT,
        )",
    )

    # appender = DuckDB.Appender(connection, "cons_indexes_highest_in_out")
    # The query below selects the filtered assets
    for row in DuckDB.query(
        connection,
        "SELECT *
        FROM t_cons_indexes
        WHERE type in ('hub', 'consumer')",
    )
        # The query below uses the assets, inflows, and outflows
        # -- The previous attempt used
        # The idea below is to find all unique time_block_start values because
        # this is uses strategy 'highest'. By ordering them, and making
        # time_block_end[i] = time_block_start[i+1] - 1, we have all ranges.
        # We use the `lead` function from SQL to get `time_block_start[i+1]`
        # and row.num_timesteps is the maximum value for when i+1 > length
        # TODO: Should be possible to do in a single SQL statement
        DuckDB.execute(
            connection,
            "INSERT INTO cons_indexes_highest_in_out
                SELECT
                    '$(row.asset)',
                    $(row.year),
                    $(row.rep_period),
                    time_block_start,
                    lead(time_block_start - 1, 1, $(row.num_timesteps))
                OVER (ORDER BY time_block_start)
                FROM (
                    SELECT time_block_start
                    FROM asset_time_resolution
                    WHERE
                        asset='$(row.asset)'
                        AND year=$(row.year)
                        AND rep_period=$(row.rep_period)
                    UNION
                    SELECT time_block_start
                    FROM flow_time_resolution
                    WHERE
                        to_asset='$(row.asset)'
                        AND year=$(row.year)
                        AND rep_period=$(row.rep_period)
                    UNION
                    SELECT time_block_start
                    FROM flow_time_resolution
                    WHERE
                        from_asset='$(row.asset)'
                        AND year=$(row.year)
                        AND rep_period=$(row.rep_period)
                )
                ",
        )
    end
end
