export GraphAssetData, GraphFlowData, RepresentativePeriod, BasePeriod, TimeBlock

const TimeBlock = UnitRange{Int}

"""
Structure to hold the data of the base periods.
"""
struct BasePeriod
    num_base_periods::Int64
end

"""
Structure to hold the data of one representative period.
"""
struct RepresentativePeriod
    mapping::Union{Nothing,Dict{Int,Float64}}  # which periods in the full problem formulation does this RP stand for
    weight::Float64
    time_steps::TimeBlock
    resolution::Float64

    function RepresentativePeriod(mapping, num_time_steps, resolution)
        weight = sum(values(mapping))
        return new(mapping, weight, 1:num_time_steps, resolution)
    end
end

"""
Structure to hold the asset data in the graph.
"""
mutable struct GraphAssetData
    type::String
    investable::Bool
    investment_integer::Bool
    investment_cost::Float64
    investment_limit::Union{Missing,Float64}
    capacity::Float64
    initial_capacity::Float64
    peak_demand::Float64
    storage_type::Union{Missing,String}
    storage_inflows::Union{Missing,Float64}
    initial_storage_capacity::Float64
    initial_storage_level::Union{Missing,Float64}
    energy_to_power_ratio::Float64
    moving_window_long_storage::Union{Missing,Int}
    profiles::Dict{Int,Vector{Float64}}
    partitions::Dict{Int,Vector{TimeBlock}}
    # Solution
    investment::Float64
    storage_level::Dict{Tuple{Int,TimeBlock},Float64}

    # You don't need profiles to create the struct, so initiate it empty
    function GraphAssetData(
        type,
        investable,
        investment_integer,
        investment_cost,
        investment_limit,
        capacity,
        initial_capacity,
        peak_demand,
        storage_type,
        storage_inflows,
        initial_storage_capacity,
        initial_storage_level,
        energy_to_power_ratio,
        moving_window_long_storage,
    )
        profiles = Dict{Int,Vector{Float64}}()
        partitions = Dict{Int,Vector{TimeBlock}}()
        return new(
            type,
            investable,
            investment_integer,
            investment_cost,
            investment_limit,
            capacity,
            initial_capacity,
            peak_demand,
            storage_type,
            storage_inflows,
            initial_storage_capacity,
            initial_storage_level,
            energy_to_power_ratio,
            moving_window_long_storage,
            profiles,
            partitions,
            -1,
            Dict{Tuple{Int,TimeBlock},Float64}(),
        )
    end
end

"""
Structure to hold the flow data in the graph.
"""
mutable struct GraphFlowData
    carrier::String
    active::Bool
    is_transport::Bool
    investable::Bool
    investment_integer::Bool
    variable_cost::Float64
    investment_cost::Float64
    investment_limit::Union{Missing,Float64}
    capacity::Float64
    initial_export_capacity::Float64
    initial_import_capacity::Float64
    efficiency::Float64
    profiles::Dict{Int,Vector{Float64}}
    partitions::Dict{Int,Vector{TimeBlock}}
    # Solution
    flow::Dict{Tuple{Int,TimeBlock},Float64}
    investment::Float64
end

function GraphFlowData(flow_data::FlowData)
    return GraphFlowData(
        flow_data.carrier,
        flow_data.active,
        flow_data.is_transport,
        flow_data.investable,
        flow_data.investment_integer,
        flow_data.variable_cost,
        flow_data.investment_cost,
        flow_data.investment_limit,
        flow_data.capacity,
        flow_data.initial_export_capacity,
        flow_data.initial_import_capacity,
        flow_data.efficiency,
        Dict{Int,Vector{Float64}}(),
        Dict{Int,Vector{TimeBlock}}(),
        Dict{Tuple{Int,TimeBlock},Float64}(),
        -1,
    )
end

"""
Structure to hold all parts of an energy problem.
"""
mutable struct EnergyProblem
    graph::MetaGraph{
        Int,
        SimpleDiGraph{Int},
        String,
        GraphAssetData,
        GraphFlowData,
        Nothing, # Internal data
        Nothing, # Edge weight function
        Nothing, # Default edge weight
    }
    representative_periods::Vector{RepresentativePeriod}
    constraints_partitions::Dict{Symbol,Dict{Tuple{String,Int},Vector{TimeBlock}}}
    base_periods::BasePeriod
    dataframes::Dict{Symbol,DataFrame}
    model::Union{JuMP.Model,Nothing}
    solved::Bool
    objective_value::Float64
    termination_status::JuMP.TerminationStatusCode

    """
        EnergyProblem(graph, representative_periods)

    Minimal constructor. The `constraints_partitions` are computed from the `representative_periods`,
    and the other fields and nothing or set to default values.
    """
    function EnergyProblem(graph, representative_periods, base_periods)
        constraints_partitions = compute_constraints_partitions(graph, representative_periods)

        return new(
            graph,
            representative_periods,
            constraints_partitions,
            base_periods,
            Dict(),
            nothing,
            false,
            NaN,
            JuMP.OPTIMIZE_NOT_CALLED,
        )
    end
end

function Base.show(io::IO, ep::EnergyProblem)
    println(io, "EnergyProblem:")
    println(io, "  - Model created: ", !isnothing(ep.model))
    println(io, "  - Solved: ", ep.solved)
    println(io, "  - Termination status: ", ep.termination_status)
    println(io, "  - Objective value: ", ep.objective_value)
end
