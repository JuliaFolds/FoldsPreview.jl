module FoldsPreviewTests

using Distributed
using LoadAllPackages
using Test

include("utils.jl")

function include_tests(m = @__MODULE__, dir = @__DIR__)
    for file in readdir(dir)
        if match(r"^test_.*\.jl$", file) !== nothing
            Base.include(m, joinpath(dir, file))
        end
    end
end

include_tests()

function collect_modules(root::Module)
    modules = Module[]
    for n in names(root, all = true)
        m = getproperty(root, n)
        m isa Module || continue
        m === root && continue
        startswith(string(nameof(m)), "Test") || continue
        push!(modules, m)
    end
    return modules
end

collect_modules() = collect_modules(@__MODULE__)


this_project() = joinpath(dirname(@__DIR__), "Project.toml")

function is_in_path()
    project = this_project()
    paths = Base.load_path()
    project in paths && return true
    realproject = realpath(project)
    realproject in paths && return true
    matches(path) = path == project || path == realproject
    return any(paths) do path
        matches(path) || matches(realpath(path))
    end
end

function with_project(f)
    is_in_path() && return f()
    load_path = copy(LOAD_PATH)
    push!(LOAD_PATH, this_project())
    try
        f()
    finally
        append!(empty!(LOAD_PATH), load_path)
    end
end

function load_me_everywhere()
    prepare_impl()
    @everywhere append!(empty!(LOAD_PATH), $(copy(LOAD_PATH)))
    pkgid = Base.PkgId(@__MODULE__)
    @everywhere Base.require($pkgid)
    @everywhere $prepare_impl()
end

function prepare_impl()
    LoadAllPackages.loadall(this_project())
end

function runtests(modules = collect_modules())
    # `with_project` and `LoadAllPackages.loadall` are for doctests
    with_project() do
        if get(ENV, "CI", "false") == "true"
            if nprocs() < 4
                addprocs(4 - nprocs())
            end
        end
        @info "Testing with:" nprocs()

        load_me_everywhere()
        runtests_impl(modules)
    end
end

function runtests_impl(modules)
    @testset "$(nameof(m))" for m in modules
        tests = map(names(m, all = true)) do n
            n == :test || startswith(string(n), "test_") || return nothing
            f = getproperty(m, n)
            f !== m || return nothing
            parentmodule(f) === m || return nothing
            applicable(f) || return nothing  # removed by Revise?
            return f
        end
        filter!(!isnothing, tests)
        @testset "$f" for f in tests
            @debug "Testing $m.$f"
            f()
        end
    end
end

end # module
