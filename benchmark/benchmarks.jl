using BenchmarkTools
using TulipaEnergyModel
using MetaGraphsNext

const SUITE = BenchmarkGroup()

SUITE["io"] = BenchmarkGroup()
SUITE["model"] = BenchmarkGroup()

const INPUT_FOLDER_BM = joinpath(@__DIR__, "..", "test", "inputs", "Norse")
const OUTPUT_FOLDER_BM = mktempdir()

SUITE["io"]["input"] = @benchmarkable begin
    create_energy_problem_from_csv_folder($INPUT_FOLDER_BM)
end
energy_problem = create_energy_problem_from_csv_folder(INPUT_FOLDER_BM)

SUITE["model"]["create_model"] = @benchmarkable begin
    create_model($energy_problem)
end

create_model!(energy_problem)

SUITE["model"]["solve_model"] = @benchmarkable begin
    solve_model!($energy_problem)
end

solve_model!(energy_problem)

SUITE["io"]["output"] = @benchmarkable begin
    save_solution_to_file($OUTPUT_FOLDER_BM, $energy_problem)
end
