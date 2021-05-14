module Utils

using Transducers: DistributedEx, ThreadedEx
using Test

in_ci() = lowercase(get(ENV, "CI", "false")) == "true"

struct NoError end

macro test_error(thrower)
    @gensym err tmp
    quote
        local $err = $NoError()
        $Test.@test try
            $thrower
            false
        catch $tmp
            $Base.@debug(
                "@test_error",
                exception = ($tmp, $catch_backtrace()),
                _module = $__module__,
                _file = $(string(__source__.file)),
                _line = $(__source__.line),
            )
            $err = $tmp
            true
        end
        $err
    end |> esc
end

function foreach_executor(f)
    @testset for ex in [ThreadedEx(), DistributedEx()]
        @debug "`$(parentmodule(f)).$f`" ex
        f(ex)
    end
end

function with_racer(f, label::Symbol; timeout = in_ci() ? 5 * 60 : 5)
    startswith(string(label), "_") && error("label must not start with __")
    endswith(string(label), "_") && error("label must not end with __")
    race = Channel{Symbol}(3) do race
        sleep(timeout)
        put!(race, :__timeout__)
        @error "`with_racer(_, :$label)`: TIMEOUT"
        close(race)
    end
    function win()
        put!(race, label)
    end
    local race_results
    try
        f(win)
    finally
        put!(race, :__done__)
        close(race)
        race_results = collect(race)
        @test race_results == [label, :__done__]
    end
    return race_results == [label, :__done__]
end

function with_racer(f, label::Symbol, rest::Symbol...; kwargs...)
    ok2 = false
    ok1 = with_racer(label; kwargs...) do win
        function wrapper(wins...)
            f(win, wins...)
        end
        ok2 = with_racer(wrapper, rest...; kwargs...)
    end
    return ok1 & ok2
end

print_error(err) = print_error(stdout, err)

function print_error(io, err::CompositeException)
    for (i, e) in enumerate(err)
        println(io)
        println(io, "$i-th error: type = $(typeof(e))")
        showerror(io, e)
    end
    println(io)
end

function print_error(io, err)
    println(io)
    println(io, "Got non-`CompositeException` exception:")
    showerror(io, err)
    println(io)
end

end  # module
