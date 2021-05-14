"""
    with_preview(f, on_preview, executor, interval::Real, [throttle]) -> result

Create a `previewer` and call `f(previewer)` whose `result` is returned as-is.

The `previewer` object passed to `f` is a transducer that acts like an identity
transducer (i.e., `Map(identity)`) with respect to the final result. However,
in another "background" task, it also calls the inner reducing function to
combine and complete the *intermediate* result and then passed it to
`on_preview`. The interval of calling `on_preview` can be configured by
`interval` and `throttle`.
"""
with_preview

"""
    with_distributed_preview(f, on_preview, interval, [throttle]) -> result

Equivalent to [`with_preview`](@ref) called with `DistributedEx` executor.
"""
with_distributed_preview

"""
    with_threaded_preview(f, on_preview, interval, [throttle]) -> result

Equivalent to [`with_preview`](@ref) called with `ThreadedEx` executor.
"""
with_threaded_preview

struct BasecaseId
    pid::typeof(myid())
    lid::UInt
end

const PROCESS_LOCAL_ID = Threads.Atomic{UInt}(0)

BasecaseId() = BasecaseId(myid(), Threads.atomic_add!(PROCESS_LOCAL_ID, UInt(1)))

remote_channel(size = 0) = RemoteChannel(() -> Channel(size))

channel_for(f, args...) = f(args...)
channel_for(::Executor, args...) = Channel(args...)
channel_for(::DistributedEx, args...) = remote_channel(args...)

struct Preview{C,S,T<:Throttle} <: Transducer
    channel::C
    start_channel::S
    throttle::T
end

with_distributed_preview(
    f,
    on_preview,
    interval::Real,
    thw::Throttle = IntervalThrottle(interval),
) = with_preview(f, on_preview, remote_channel, interval, thw)

with_threaded_preview(
    f,
    on_preview,
    thw::Throttle,
    interval::Real = IntervalThrottle(interval),
) = with_preview(f, on_preview, Channel, thw, interval)

function with_preview(f, on_preview, make_channel, th::IntervalThrottle)
    @warn(
        "DEPRECATED: Please use `with_preview(f, on_preview, executor, interval)`" *
        " instead of `with_preview(f, on_preview, executor, IntervalThrottle(interval))`",
        maxlog = 2,
    )
    return with_preview(f, on_preview, make_channel, th.interval)
end

function with_preview(
    f,
    on_preview,
    make_channel,
    interval::Real,
    thw::Throttle = IntervalThrottle(interval),
)
    interval >= 0 || error("`interval` must be positive; got: interval = $interval")
    # TODO: better buffer size detection
    channel = channel_for(make_channel, Threads.nthreads() * nprocs())
    start_channel = channel_for(make_channel, 0)
    previewer = Preview(channel, start_channel, thw)
    accref = LockedRef{Any}()
    isdone() = !isopen(channel)
    @sync try
        @async try
            updater_loop(accref, previewer)
        catch err
            @debug "`updater_loop` task" exception = (err, catch_backtrace())
            rethrow()
        finally
            close(channel)
            close(start_channel)
            close(accref)
        end
        @async try
            preview_loop(on_preview, interval, accref, isdone)
        catch err
            @debug "`preview_loop` task" exception = (err, catch_backtrace())
            rethrow()
        finally
            close(channel)
            close(start_channel)
            close(accref)
        end
        @syncthrow f(previewer)
    finally
        close(channel)
        close(start_channel)
        close(accref)
    end
end

# A very hacky solution for using the reducing function in `preview_loop`.
# Ideally, we can do something like this via fold initialization protocol.
function send_start!(start_channel, starter)
    try
        put!(start_channel, starter)
    catch err
        # Errors here are expected here since `start_channel` will be closed
        # after the first element is taken.
        # @debug "`send_start!`" exception = (err, catch_backtrace())
    end
    return
end

function preview_loop(on_preview, interval, accref, isdone)
    acc0 = tryfetch(accref)
    acc0 === nothing && return
    function preview_loop_impl()
        on_preview(something(acc0))
        while true
            # @info "`preview_loop`: Sleeping $interval seconds..."
            sleep(interval)
            isdone() && return
            local acc = tryfetch(accref)
            acc === nothing && return
            on_preview(something(acc))
        end
    end
    Base.invokelatest(preview_loop_impl)
end

function updater_loop(accref, previewer)
    rf, init = try
        take!(previewer.start_channel)
    catch err
        @debug "`updater_loop`: on `take!(start_channel)`" exception =
            (err, catch_backtrace())
        return
    end
    close(previewer.start_channel)
    Base.invokelatest(updater_loop, accref, previewer, rf, init)
end

function updater_loop(accref, previewer, rf, init)
    channel = previewer.channel
    accs = Dict{BasecaseId,Any}()
    while true
        bid, a = try
            take!(channel)
        catch err
            @debug "`updater_loop`: on `take!(channel)`" exception =
                (err, catch_backtrace())
            return
        end
        accs[bid] = a

        # TODO: use monoid cached tree
        acc = start(rf, init)
        for x in values(accs)
            acc = combine(rf, acc, x)
        end
        tryset!(accref, complete(rf, acc)) || break
    end
end

function Transducers.start(rf::R_{Preview}, init)
    iacc = start(inner(rf), init)
    bid = BasecaseId()
    tstate = Throttles.init(xform(rf).throttle)
    return wrap(rf, (bid, tstate, false, init), iacc)
end

Transducers.next(rf::R_{Preview}, acc, input) =
    wrapping(rf, acc) do (bid, tstate, started, init), iacc
        iacc = next(inner(rf), iacc, input)
        go, tstate = Throttles.step(xform(rf).throttle, tstate)
        if go
            if !started
                send_start!(xform(rf).start_channel, (inner(rf), init))
            end
            started = true
            put!(xform(rf).channel, (bid, iacc))
        end
        return (bid, tstate, started, init), iacc
    end
# Note: Postpone `send_start!` until we hit the first `go`. Otherwise, with
# `ThreadedEx` and alike, each base case `Task` will hit the yield point right
# after it is started. It makes the scheduler to (likely) re-use the OS thread
# (which is very bad for performance).

Transducers.complete(rf::R_{Preview}, acc) = complete(inner(rf), last(unwrap(rf, acc)))

function Transducers.combine(rf::R_{Preview}, a, b)
    (bid, tstatea, starteda, init), ira = unwrap(rf, a)
    (_, tstateb, startedb), irb = unwrap(rf, b)
    irc = combine(inner(rf), ira, irb)
    go, tstatea = Throttles.step(xform(rf).throttle, tstatea)
    if !go
        go, _ = Throttles.step(xform(rf).throttle, tstateb)
    end
    started = starteda || startedb
    if go
        if started
            send_start!(xform(rf).start_channel, (inner(rf), init))
        end
        started = true
        put!(xform(rf).channel, (bid, irc))
    end
    return wrap(rf, (bid, tstatea, started, init), irc)
end
