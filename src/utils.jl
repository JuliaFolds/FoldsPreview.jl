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

@enum RefState begin
    REF_UNSET
    REF_SET
    REF_CLOSED
end

struct LockedRef{T}
    ref::Base.RefValue{T}
    state::Base.RefValue{RefState}
    cond::Threads.Condition
end

LockedRef{T}() where {T} = LockedRef{T}(Ref{T}(), Ref(REF_UNSET), Threads.Condition())
LockedRef(x) = LockedRef(Ref(x), Ref(REF_SET), Threads.Condition())

function tryfetch(ref::LockedRef)
    lock(ref.cond) do
        while true
            state = ref.state[]
            state == REF_SET && return Some(ref.ref[])
            state == REF_CLOSED && return nothing
            wait(ref.cond)
        end
    end
end

function tryset!(ref::LockedRef, value)
    lock(ref.cond) do
        state = ref.state[]
        state == REF_CLOSED && return false
        ref.state[] = REF_SET
        ref.ref[] = value
        state == REF_UNSET && notify(ref.cond)
        return true
    end
end

function Base.close(ref::LockedRef)
    lock(ref.cond) do
        ref.state[] = REF_CLOSED
        notify(ref.cond)
    end
end
