export GraphAssetData, GraphFlowData, RepresentativePeriod, TimeBlock

const TimeBlock = UnitRange{Int}

"""
Structure to hold the data of one representative period.
"""
struct RepresentativePeriod
    weight::Float64
    time_steps::TimeBlock
    resolution::Float64

    function RepresentativePeriod(weight, num_time_steps, resolution)
        return new(weight, 1:num_time_steps, resolution)
    end
end

"""
Structure to hold the asset data in the graph.
"""
mutable struct GraphAssetData
    type::String
    investable::Bool
    investment_cost::Float64
    investment_limit::Union{Missing,Float64}
    capacity::Float64
    initial_capacity::Float64
    peak_demand::Float64
    initial_storage_capacity::Float64
    initial_storage_level::Float64
    energy_to_power_ratio::Float64
    profiles::Dict{Int,Vector{Float64}}
    partitions::Dict{Int,Vector{TimeBlock}}
    # Solution
    investment::Int
    storage_level::Dict{Tuple{Int,TimeBlock},Float64}

    # You don't need profiles to create the struct, so initiate it empty
    function GraphAssetData(
        type,
        investable,
        investment_cost,
        investment_limit,
        capacity,
        initial_capacity,
        peak_demand,
        initial_storage_capacity,
        initial_storage_level,
        energy_to_power_ratio,
    )
        profiles = Dict{Int,Vector{Float64}}()
        partitions = Dict{Int,Vector{TimeBlock}}()
        return new(
            type,
            investable,
            investment_cost,
            investment_limit,
            capacity,
            initial_capacity,
            peak_demand,
            initial_storage_capacity,
            initial_storage_level,
            energy_to_power_ratio,
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
    variable_cost::Float64
    investment_cost::Float64
    investment_limit::Union{Missing,Float64}
    import_capacity::Float64
    export_capacity::Float64
    unit_capacity::Float64
    initial_capacity::Float64
    efficiency::Float64
    profiles::Dict{Int,Vector{Float64}}
    partitions::Dict{Int,Vector{TimeBlock}}
    # Solution
    flow::Dict{Tuple{Int,TimeBlock},Float64}
    investment::Int
end

function GraphFlowData(flow_data::FlowData)
    return GraphFlowData(
        flow_data.carrier,
        flow_data.active,
        flow_data.is_transport,
        flow_data.investable,
        flow_data.variable_cost,
        flow_data.investment_cost,
        flow_data.investment_limit,
        flow_data.import_capacity,
        flow_data.export_capacity,
        max(flow_data.export_capacity, flow_data.import_capacity),
        flow_data.initial_capacity,
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
    constraints_partitions::Dict{String,Dict{Tuple{String,Int},Vector{TimeBlock}}}
    model::Union{JuMP.Model,Nothing}
    solved::Bool
    objective_value::Float64
    termination_status::JuMP.TerminationStatusCode
    # solver_parameters # Part of #246

    """
        EnergyProblem(graph, representative_periods)

    Minimal constructor. The `constraints_partitions` are computed from the `representative_periods`,
    and the other fields and nothing or set to default values.
    """
    function EnergyProblem(graph, representative_periods)
        constraints_partitions = Dict{String,Dict{Tuple{String,Int},Vector{TimeBlock}}}()

        constraints_partitions["lowest_resolution"] =
            compute_constraints_partitions(graph, representative_periods; strategy = :greedy) # used mainly for energy constraints
        constraints_partitions["highest_resolution"] =
            compute_constraints_partitions(graph, representative_periods; strategy = :all)    # used mainly for capacity constraints

        return new(
            graph,
            representative_periods,
            constraints_partitions,
            nothing,
            false,
            NaN,
            JuMP.OPTIMIZE_NOT_CALLED,
        )
    end
end
