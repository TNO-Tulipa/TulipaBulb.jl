export add_transport_constraints!

"""
add_transport_constraints!(model, graph, df_flows, flow, Ft, flows_investment)

Adds the transport flow constraints to the model.
"""
function add_transport_constraints!(connection, model, variables, constraints, profiles)
    ## unpack from model
    accumulated_flows_export_units = model[:accumulated_flows_export_units]
    accumulated_flows_import_units = model[:accumulated_flows_import_units]

    let table_name = :transport_flow_limit, cons = constraints[table_name]
        indices = _append_transport_data_to_indices(connection)
        var_flow = variables[:flow].container

        availability_agg_iterator = (
            _profile_aggregate(
                profiles.rep_period,
                (row.profile_name, row.year, row.rep_period),
                row.time_block_start:row.time_block_end,
                Statistics.mean,
                1.0,
            ) for row in indices
        )

        # - Create upper limit of transport flow
        attach_expression!(
            cons,
            :upper_bound_transport_flow,
            [
                @expression(
                    model,
                    availability_agg *
                    row.capacity *
                    accumulated_flows_export_units[row.year, (row.from, row.to)]
                ) for (row, availability_agg) in zip(indices, availability_agg_iterator)
            ],
        )

        # - Create lower limit of transport flow
        attach_expression!(
            cons,
            :lower_bound_transport_flow,
            [
                @expression(
                    model,
                    availability_agg *
                    row.capacity *
                    accumulated_flows_import_units[row.year, (row.from, row.to)]
                ) for (row, availability_agg) in zip(indices, availability_agg_iterator)
            ],
        )

        ## Constraints that define bounds for an investable transport flow

        # - Max transport flow limit
        attach_constraint!(
            model,
            cons,
            :max_transport_flow_limit,
            [
                @constraint(
                    model,
                    var_flow[row.var_flow_index] ≤ upper_bound_transport_flow,
                    base_name = "max_transport_flow_limit[($(row.from),$(row.to)),$(row.year),$(row.rep_period),$(row.time_block_start):$(row.time_block_end)]"
                ) for (row, upper_bound_transport_flow) in
                zip(indices, cons.expressions[:upper_bound_transport_flow])
            ],
        )

        # - Min transport flow limit
        attach_constraint!(
            model,
            cons,
            :min_transport_flow_limit,
            [
                @constraint(
                    model,
                    var_flow[row.var_flow_index] ≥ -lower_bound_transport_flow,
                    base_name = "min_transport_flow_limit[($(row.from),$(row.to)),$(row.year),$(row.rep_period),$(row.time_block_start):$(row.time_block_end)]"
                ) for (row, lower_bound_transport_flow) in
                zip(indices, cons.expressions[:lower_bound_transport_flow])
            ],
        )
    end
end

function _append_transport_data_to_indices(connection)
    return DuckDB.query(
        connection,
        "SELECT
            cons.*,
            flow.capacity,
            flows_profiles.profile_name,
        FROM cons_transport_flow_limit AS cons
        LEFT JOIN flow
            ON cons.from = flow.from_asset
            AND cons.to = flow.to_asset
        LEFT OUTER JOIN flows_profiles
            ON cons.from = flows_profiles.from_asset
            AND cons.to = flows_profiles.to_asset
            AND cons.year = flows_profiles.year
            AND flows_profiles.profile_type = 'availability'
        ORDER BY cons.index
        ",
    )
end
