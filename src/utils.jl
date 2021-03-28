"""
    @syncthrow ex

Equivalent to just `ex` but let `@sync` include the exception thrown from
`ex` to `CompositeException`.
"""
macro syncthrow(ex)
    @gensym err
    quote
        $Base.@isdefined($(Base.sync_varname)) ||
            $error("`@syncthrow` requires outer `@sync`")
        try
            $ex
        catch $err
            # $Base.@debug "@syncthrow" exception = ($err, catch_backtrace())
            $Base.@sync_add $Thrower($err, $catch_backtrace())
        end
    end |> esc
end

const BacktraceType = try
    error("")
catch
    catch_backtrace()
end |> typeof

struct Thrower <: Exception
    err::Any
    backtrace::BacktraceType
end

Base.wait(t::Thrower) = throw(t)

function Base.showerror(io::IO, t::Thrower)
    print(io, "Thrower: ")
    showerror(io, t.err, t.backtrace)
end
