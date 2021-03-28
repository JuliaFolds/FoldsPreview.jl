module Utils

using Transducers: DistributedEx, ThreadedEx
using Test

macro test_error(thrower)
    @gensym err tmp
    quote
        local $err
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
