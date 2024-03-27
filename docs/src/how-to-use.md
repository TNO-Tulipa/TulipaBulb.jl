# [How to Use](@id how-to-use)

```@contents
Pages = ["how-to-use.md"]
Depth = 5
```

## Install

In Julia:

-   Enter package mode (press "]")

```julia-pkg
pkg> add TulipaEnergyModel
```

-   Return to Julia mode (backspace)

```julia
julia> using TulipaEnergyModel
```

Optional (takes a minute or two):

-   Enter package mode (press "]")

```julia-pkg
pkg> test TulipaEnergyModel
```

(All tests should pass.)

## Run Scenario

To run a scenario, use the function:

-   [`run_scenario(input_folder)`](@ref)
-   [`run_scenario(input_folder, output_folder)`](@ref)

The input_folder should contain CSV files as described below. The output_folder is optional if the user wants to export the output.

## Input

Currently, we only accept input from CSV files.
They should each follow the specification of input structures.
You can also check the [`test/inputs` folder](https://github.com/TulipaEnergy/TulipaEnergyModel.jl/tree/main/test/inputs) for examples.

### CSV

Below, we have a description of the files.
At the end, in [Schemas](@ref), we have the expected columns in these CSVs.

#### [`assets-data.csv`](@id assets-data)

This file includes the list of assets and the data associated with each of them.

The `Missing` data meaning depends on the parameter, for instance:

-   `investment_limit`: There is no investment limit.
-   `initial_storage_level`: The initial storage level is free (between the storage level limits), meaning that the optimization problem decides the best starting point for the storage asset. In addition, the first and last time blocks in a representative period are linked to create continuity in the storage level.

#### [`flows-data.csv`](@id flows-data)

Similar to `assets-data.csv`, but for flows. Each flow is defined as a pair of assets.

The `Missing` data meaning depends on the parameter, for instance:

-   `investment_limit`: There is no investment limit.

#### `assets-timeframe-profiles.csv` and `assets-rep-periods-profiles.csv`

These files contain information about assets and their associated profiles. Each row lists an asset, the type of profile (e.g., availability, demand, maximum or minimum storage level), and the profile's name. The timeframe profiles are used in the inter-temporal constraints, whereas the representative periods profiles are used in the intra-temporal constraints.

#### `flows-rep-periods-profiles.csv`

Similar to their `asset` counterpart.

#### `profiles-timeframe-<type>.csv` and `profiles-rep-periods-<type>.csv`

One of these files must exist for each `type` defined in either `assets-*-periods-profiles` or `flows-rep-periods-profiles`. For example, if the file `assets-rep-periods-profiles.csv` defines an availability profile, the file `profiles-rep-periods-availability.csv` includes the profile data. The files store the profile data as indexed by a profile name.

#### [`assets-rep-periods-partitions.csv`](@id asset-rep-periods-partitions-definition)

Contains a description of the [partition](@ref Partition) for each asset with respect to representative periods.
If not specified, each asset will have the exact time resolution as the representative period.

To specify the desired resolution, there are currently three options, based on the value of the column `specification`.
The column `partition` serves to define the partitions in the specification given by the column `specification`.

-   `specification = uniform`: Set the resolution to a uniform amount, i.e., a time block is made of X time steps. The number X is defined in the column `partition`. The number of time steps in the representative period must be divisible by `X`.
-   `specification = explicit`: Set the resolution according to a list of numbers separated by `;` on the `partition`. Each number in the list is the number of time steps for that time block. For instance, `2;3;4` means that there are three time blocks, the first has 2 time steps, the second has 3 time steps, and the last has 4 time steps. The sum of the number of time steps must be equal to the total number of time steps in that representative period.
-   `specification = math`: Similar to explicit, but using `+` and `x` to give the number of time steps. The value of `partition` is a sequence of elements of the form `NxT` separated by `+`. `NxT` means `N` time blocks of length `T`.

The table below shows various results for different formats for a representative period with 12 time steps.

| Time Block            | :uniform | :explicit               | :math       |
| :-------------------- | :------- | :---------------------- | :---------- |
| 1:3, 4:6, 7:9, 10:12  | 3        | 3;3;3;3                 | 4x3         |
| 1:4, 5:8, 9:12        | 4        | 4;4;4                   | 3x4         |
| 1:1, 2:2, …, 12:12    | 1        | 1;1;1;1;1;1;1;1;1;1;1;1 | 12x1        |
| 1:3, 4:6, 7:10, 11:12 | NA       | 3;3;4;2                 | 2x3+1x4+1x2 |

#### [`flows-rep-periods-partitions.csv`](@id flow-rep-periods-partitions-definition)

Similar to `assets-rep-periods-partitions.csv`, but for flows.

#### [`assets-timeframe-partitions.csv`](@id assets-timeframe-partitions)

Similar to their `rep-periods` counterpart, but for the periods in the [timeframe](@ref timeframe) of the model.

#### `rep-periods-data.csv`

Describes the [representative periods](@ref representative-periods).

#### [`rep-periods-mapping.csv`](@id rep-periods-mapping)

Describes the periods of the [timeframe](@ref timeframe) that map into a [representative period](@ref representative-periods) and the weight of the representative period in them.

#### Schemas

```@eval
using Markdown, TulipaEnergyModel

Markdown.parse(
    join(["- **$filename**\n" *
        join(
            ["  - `$f: $t`" for (f, t) in schema],
            "\n",
        ) for (filename, schema) in TulipaEnergyModel.schema_per_file
    ] |> sort, "\n")
)
```

## Structures

The list of relevant structures used in this package are listed below:

### EnergyProblem

The `EnergyProblem` structure is a wrapper around various other relevant structures.
It hides the complexity behind the energy problem, making the usage more friendly, although more verbose.

#### Fields

-   `graph`: The [Graph](@ref) object that defines the geometry of the energy problem.
-   `representative_periods`: A vector of [Representative Periods](@ref representative-periods).
-   `constraints_partitions`: Dictionaries that connect pairs of asset and representative periods to [time partitions (vectors of time blocks)](@ref Partition).
-   `timeframe`: The number of periods of the `representative_periods`.
-   `dataframes`: The data frames used to linearize the variables and constraints. These are used internally in the model only.
-   `model`: A JuMP.Model object representing the optimization model.
-   `solution`: A structure of the variable values (investments, flows, etc) in the solution.
-   `solved`: A boolean indicating whether the `model` has been solved or not.
-   `objective_value`: The objective value of the solved problem.
-   `termination_status`: The termination status of the optimization model.
-   `time_read_data`: Time taken for reading the data (in seconds).
-   `time_create_model`: Time taken for creating the model (in seconds).
-   `time_solve_model`: Time taken for solving the model (in seconds).

#### Constructor

The `EnergyProblem` can also be constructed using the minimal constructor below.

-   `EnergyProblem(graph, representative_periods, timeframe)`: Constructs a new `EnergyProblem` object with the given graph, representative periods, and timeframe. The `constraints_partitions` field is computed from the `representative_periods`, and the other fields are initialized with default values.

See the [basic example tutorial](@ref basic-example) to see how these can be used.

### Graph

The energy problem is defined using a graph.
Each vertex is an asset, and each edge is a flow.

We use [MetaGraphsNext.jl](https://github.com/JuliaGraphs/MetaGraphsNext.jl) to define the graph and its objects.
Using MetaGraphsNext we can define a graph with metadata, i.e., associate data with each asset and flow.
Furthermore, we can define the labels of each asset as keys to access the elements of the graph.
The assets in the graph are of type [GraphAssetData](@ref), and the flows are of type [GraphFlowData](@ref).

The graph can be created using the [`create_graph_and_representative_periods_from_csv_folder`](@ref) function, or it can be accessed from an [EnergyProblem](@ref).

See how to use the graph in the [graph tutorial](@ref graph-tutorial).

### GraphAssetData

This structure holds all the information of a given asset.
These are stored inside the [Graph](@ref).
Given a graph `graph`, an asset `a` can be accessed through `graph[a]`.

### GraphFlowData

This structure holds all the information of a given flow.
These are stored inside the [Graph](@ref).
Given a graph `graph`, a flow `(u, v)` can be accessed through `graph[u, v]`.

### Partition

A [representative period](@ref representative-periods) will be defined with a number of time steps.
A partition is a division of these time steps into [time blocks](@ref time-blocks) such that the time blocks are disjunct and that all time steps belong to some time block.
Some variables and constraints are defined over every time block in a partition.

For instance, for a representative period with 12 time steps, all sets below are partitions:

-   `\{\{1, 2, 3\}, \{4, 5, 6\}, \{7, 8, 9\}, \{10, 11, 12\}\}`
-   `\{\{1, 2, 3, 4\}, \{5, 6, 7, 8\}, \{9, 10, 11, 12\}\}`
-   `\{\{1\}, \{2, 3\}, \{4\}, \{5, 6, 7, 8\}, \{9, 10, 11, 12\}\}`

### [Timeframe](@id timeframe)

The timeframe is the total period we want to analyze with the model, usually a year, but it can be any other time definition. A timeframe has two fields:

-   `num_periods`: The timeframe is defined by a certain number of periods. For instance, a year can be defined by 365 periods, each describing a day.
-   `map_periods_to_rp`: Indicates the periods of the timeframe that map into a [representative period](@ref representative-periods) and the weight of the representative period in them.

### [Representative Periods](@id representative-periods)

The [timeframe](@ref timeframe) (e.g., a full year) is described by a selection of representative periods, for instance, days or weeks, that nicely summarize other similar periods. For example, we could model the year into 3 days, by clustering all days of the year into 3 representative days. Each one of these days is called a representative period. _TulipaEnergyModel.jl_ has the flexibility to consider representative periods of different lengths for the same timeframe (e.g., a year can be represented by a set of 4 days and 2 weeks). To obtain the representative periods, we recommend using [TulipaClustering](https://github.com/TulipaEnergy/TulipaClustering.jl).

A representative period has four fields:

-   `mapping`: Indicates the periods of the [timeframe](@ref timeframe) that map into a representative period and the weight of the representative period in them.
-   `weight`: Indicates how many representative periods are contained in the [timeframe](@ref timeframe); this is inferred automatically from `mapping`.
-   `timesteps`: The number of timesteps blocks in the representative period.
-   `resolution`: The duration in time of a time step.

The number of time steps and resolution work together to define the coarseness of the period.
Nothing is defined outside of these time steps, so, for instance, if the representative period represents a day and you want to specify a variable or constraint with a coarseness of 30 minutes. You need to define the number of time steps to 48 and the resolution to `0.5`.

### Solution

The solution object `energy_problem.solution` is a mutable struct with the following fields:

-   `assets_investment[a]`: The investment for each asset, indexed on the investable asset `a`.
-   `flows_investment[u, v]`: The investment for each flow, indexed on the investable flow `(u, v)`.
-   `storage_level_intra_rp[a, rp, timesteps_block]`: The storage level for the storage asset `a` within (intra) a representative period `rp` and a time block `timesteps_block`. The list of time blocks is defined by `constraints_partitions`, which was used to create the model.
-   `storage_level_inter_rp[a, pb]`: The storage level for the storage asset `a` between (inter) representative periods in the periods block `pb`.
-   `flow[(u, v), rp, timesteps_block]`: The flow value for a given flow `(u, v)` at a given representative period. `rp`, and time block `timesteps_block`. The list of time blocks is defined by `graph[(u, v)].partitions[rp]`.
-   `objective_value`: A Float64 with the objective value at the solution.
-   `duals`: A Dict containing the dual variables of selected constraints.

Check the [tutorial](@ref solution-tutorial) for tips on manipulating the solution.

### [Time Blocks](@id time-blocks)

A time block is a range for which a variable or constraint is defined.
It is a range of numbers, i.e., all integer numbers inside an interval.
Time blocks are used for the periods in the [timeframe](@ref timeframe) and the timesteps in the [representative period](@ref representative-periods).

## [Exploring infeasibility](@id infeasible)

If your model is infeasible, you can try exploring the infeasibility with [JuMP.compute_conflict!](https://jump.dev/JuMP.jl/stable/api/JuMP/#JuMP.compute_conflict!) and [JuMP.copy_conflict](https://jump.dev/JuMP.jl/stable/api/JuMP/#JuMP.copy_conflict). Use `energy_problem.model` for the model argument. For instance:

```julia
if energy_problem.termination_status == INFEASIBLE
 compute_conflict!(energy_problem.model)
 iis_model, reference_map = copy_conflict(energy_problem.model)
 print(iis_model)
end
```

> **Note:** Not all solvers support this functionality.
