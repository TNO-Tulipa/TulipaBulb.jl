function create_multi_year_expressions!(connection, model, variables, expressions)
    # The variable assets_decommission is defined for (a, my, cy)
    # The capacity expression that we need to compute is
    #
    #   profile_times_capacity[a, my] = ∑_cy agg(
    #     profile[
    #       profile_name[a, cy, 'availability'],
    #       my,
    #       rp
    #     ],
    #     time_block
    #   ) * accumulated_units[a, my, cy]
    #
    # where
    #
    # - a=asset, my=milestone_year, cy=commission_year, rp=rep_period
    # - profile_name[a, cy, 'availability']: name of profile for (a, cy, 'availability')
    # - profile[p_name, my, rp]: profile vector named `p_name` for my and rp (or some default value, ignored here)
    # - agg(p_vector, time_block): some aggregation of vector p_vector over time_block
    #
    # and
    #
    #   accumulated_units[a, my, cy] =
    #       initial_units[a, my, cy] +
    #       investment_units[a, cy] -
    #       ∑_{past_my: past_my ≤ my} assets_decommission[a, past_my, cy]
    #
    # Assumption:
    # - asset_both exists only for (a,my,cy) where technical lifetime was already taken into account

    _create_multi_year_expressions_indices!(connection, expressions)

    let table_name = :accumulated_units, expr = expressions[table_name]
        var_inv = variables[:assets_investment].container
        var_dec = variables[:assets_decommission].container

        indices = DuckDB.query(connection, "FROM expr_$table_name ORDER BY index")
        attach_expression!(
            expr,
            :assets,
            JuMP.AffExpr[
                if ismissing(row.var_decommission_indices) && ismissing(row.var_investment_index)
                    @expression(model, row.initial_units)
                elseif ismissing(row.var_investment_index)
                    @expression(
                        model,
                        row.initial_units -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                elseif ismissing(row.var_decommission_indices)
                    @expression(model, row.initial_units + var_inv[row.var_investment_index])
                else
                    @expression(
                        model,
                        row.initial_units + var_inv[row.var_investment_index] -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                end for row in indices
            ],
        )

        var_energy_inv = variables[:assets_investment_energy].container
        var_energy_dec = variables[:assets_decommission_energy].container

        attach_expression!(
            expr,
            :assets_energy,
            JuMP.AffExpr[
                if ismissing(row.var_energy_decommission_indices) &&
                   ismissing(row.var_energy_investment_index)
                    @expression(model, row.initial_storage_units)
                elseif ismissing(row.var_energy_investment_index)
                    @expression(
                        model,
                        row.initial_storage_units -
                        sum(var_energy_dec[idx] for idx in row.var_energy_decommission_indices)
                    )
                elseif ismissing(row.var_energy_decommission_indices)
                    @expression(
                        model,
                        row.initial_storage_units + var_energy_inv[row.var_energy_investment_index]
                    )
                else
                    @expression(
                        model,
                        row.initial_storage_units +
                        var_energy_inv[row.var_energy_investment_index] -
                        sum(var_energy_dec[idx] for idx in row.var_energy_decommission_indices)
                    )
                end for row in indices
            ],
        )
    end

    let table_name = :accumulated_flow_units, expr = expressions[table_name]
        var_inv = variables[:flows_investment].container
        var_dec = variables[:flows_decommission].container

        indices = DuckDB.query(connection, "FROM expr_$table_name ORDER BY index")
        attach_expression!(
            expr,
            :export,
            JuMP.AffExpr[
                if ismissing(row.var_decommission_indices) && ismissing(row.var_investment_index)
                    @expression(model, row.initial_export_units)
                elseif ismissing(row.var_investment_index)
                    @expression(
                        model,
                        row.initial_export_units -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                elseif ismissing(row.var_decommission_indices)
                    @expression(
                        model,
                        row.initial_export_units + var_inv[row.var_investment_index]
                    )
                else
                    @expression(
                        model,
                        row.initial_export_units + var_inv[row.var_investment_index] -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                end for row in indices
            ],
        )

        attach_expression!(
            expr,
            :import,
            JuMP.AffExpr[
                if ismissing(row.var_decommission_indices) && ismissing(row.var_investment_index)
                    @expression(model, row.initial_import_units)
                elseif ismissing(row.var_investment_index)
                    @expression(
                        model,
                        row.initial_import_units -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                elseif ismissing(row.var_decommission_indices)
                    @expression(
                        model,
                        row.initial_import_units + var_inv[row.var_investment_index]
                    )
                else
                    @expression(
                        model,
                        row.initial_import_units + var_inv[row.var_investment_index] -
                        sum(var_dec[idx] for idx in row.var_decommission_indices)
                    )
                end for row in indices
            ],
        )
    end
end

function _create_multi_year_expressions_indices!(connection, expressions)
    DuckDB.query(
        connection,
        "
        CREATE OR REPLACE TEMP SEQUENCE id START 1;
        CREATE OR REPLACE TABLE expr_accumulated_units AS
        SELECT
            nextval('id') AS index,
            asset_both.asset AS asset,
            asset_both.milestone_year AS milestone_year,
            asset_both.commission_year AS commission_year,
            ANY_VALUE(asset_both.initial_units) AS initial_units,
            ANY_VALUE(asset_both.initial_storage_units) AS initial_storage_units,
            ARRAY_AGG(var_dec.index) FILTER (var_dec.index IS NOT NULL) AS var_decommission_indices,
            ANY_VALUE(var_inv.index) AS var_investment_index,
            ARRAY_AGG(var_energy_dec.index) FILTER (var_energy_dec.index IS NOT NULL) AS var_energy_decommission_indices,
            ANY_VALUE(var_energy_inv.index) AS var_energy_investment_index,
        FROM asset_both
        LEFT JOIN var_assets_decommission AS var_dec
            ON asset_both.asset = var_dec.asset
            AND asset_both.commission_year = var_dec.commission_year
            AND asset_both.milestone_year >= var_dec.milestone_year
        LEFT JOIN var_assets_investment AS var_inv
            ON asset_both.asset = var_inv.asset
            AND asset_both.commission_year = var_inv.milestone_year
        LEFT JOIN var_assets_decommission_energy AS var_energy_dec
            ON asset_both.asset = var_energy_dec.asset
            AND asset_both.commission_year = var_energy_dec.commission_year
            AND asset_both.milestone_year >= var_energy_dec.milestone_year
        LEFT JOIN var_assets_investment_energy AS var_energy_inv
            ON asset_both.asset = var_energy_inv.asset
            AND asset_both.commission_year = var_energy_inv.milestone_year
        GROUP BY asset_both.asset, asset_both.milestone_year, asset_both.commission_year
        ",
    )

    DuckDB.query(
        connection,
        "
        CREATE OR REPLACE TEMP SEQUENCE id START 1;
        CREATE OR REPLACE TABLE expr_accumulated_flow_units AS
        SELECT
            nextval('id') AS index,
            flow_both.from_asset AS from_asset,
            flow_both.to_asset AS to_asset,
            flow_both.milestone_year AS milestone_year,
            flow_both.commission_year AS commission_year,
            ANY_VALUE(flow_both.initial_export_units) AS initial_export_units,
            ANY_VALUE(flow_both.initial_import_units) AS initial_import_units,
            ARRAY_AGG(var_dec.index) FILTER (var_dec.index IS NOT NULL) AS var_decommission_indices,
            ANY_VALUE(var_inv.index) AS var_investment_index,
        FROM flow_both
        LEFT JOIN var_flows_decommission AS var_dec
            ON flow_both.to_asset = var_dec.to_asset
            AND flow_both.from_asset = var_dec.from_asset
            AND flow_both.commission_year = var_dec.commission_year
            AND var_dec.milestone_year <= flow_both.milestone_year
        LEFT JOIN var_flows_investment AS var_inv
            ON flow_both.to_asset = var_inv.to_asset
            AND flow_both.from_asset = var_inv.from_asset
            AND flow_both.commission_year = var_inv.milestone_year
        GROUP BY flow_both.from_asset, flow_both.to_asset, flow_both.milestone_year, flow_both.commission_year
        ",
    )

    for expr_name in (:accumulated_units, :accumulated_flow_units)
        expressions[expr_name] = TulipaExpression(connection, "expr_$expr_name")
    end

    return nothing
end
