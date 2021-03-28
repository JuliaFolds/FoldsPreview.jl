"""
    with_preview(f, on_preview, executor, throttle, [throttle_local]) -> result

Create a `previewer` and call `f(previewer)` whose `result` is returned as-is.

The `previewer` object passed to `f` is a transducer that acts like an identity
transducer (i.e., `Map(identity)`) with respect to the final result. However,
in another "background" task, it also calls the inner reducing function to
combine and complete the *intermediate* result and then passed it to
`on_preview`. The interval of calling `on_preview` can be configured by
`throttle` and `throttle_local`. The first `throttle` controls how often each
"worker" (a process for `DistributedEx` and a `Task` for `ThreadedEx` and
alike) tries to share its accumulator and `throttle_local` controls how often
the local "preview event loop" actually calls `on_preview` function.
"""
with_preview

"""
    with_distributed_preview(f, on_preview, throttle, [throttle_local]) -> result

Equivalent to [`with_preview`](@ref) called with `DistributedEx` executor.
"""
with_distributed_preview

"""
    with_threaded_preview(f, on_preview, throttle, [throttle_local]) -> result

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

with_distributed_preview(f, on_preview, th::Throttle) =
    with_distributed_preview(f, on_preview, th, th)
with_distributed_preview(f, on_preview, thw::Throttle, thp::Throttle) =
    with_preview(f, on_preview, remote_channel, thw, thp)

with_threaded_preview(f, on_preview, th::Throttle) =
    with_threaded_preview(f, on_preview, th, th)
with_threaded_preview(f, on_preview, thw::Throttle, thp::Throttle) =
    with_preview(f, on_preview, Channel, thw, thp)

with_preview(f, on_preview, make_channel, th::Throttle) =
    with_preview(f, on_preview, make_channel, th, th)
function with_preview(f, on_preview, make_channel, thw::Throttle, thp::Throttle)
    # TODO: better buffer size detection
    channel = channel_for(make_channel, Threads.nthreads() * nprocs())
    start_channel = channel_for(make_channel, 0)
    previewer = Preview(channel, start_channel, thw)
    @sync try
        @async try
            preview_loop(on_preview, previewer, thp)
        catch err
            @debug "`preview_loop` task" exception = (err, catch_backtrace())
            rethrow()
        finally
            close(channel)
            close(start_channel)
        end
        @syncthrow f(previewer)
    finally
        close(channel)
        close(start_channel)
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

function preview_loop(on_preview, previewer, th)
    rf, init = try
        take!(previewer.start_channel)
    catch err
        @debug "`preview_loop`: on `take!(start_channel)`" exception =
            (err, catch_backtrace())
        return
    end
    close(previewer.start_channel)
    Base.invokelatest(preview_loop, on_preview, previewer, th, rf, init)
end

function preview_loop(on_preview, previewer, th, rf, init)
    channel = previewer.channel
    accs = Dict{BasecaseId,Any}()
    tstate = Throttles.init(th)
    while true
        bid, a = try
            take!(channel)
        catch err
            @debug "`preview_loop`: on `take!(channel)`" exception =
                (err, catch_backtrace())
            return
        end
        accs[bid] = a
        go, tstate = Throttles.step(th, tstate)
        # print("go = $go; tstate = $tstate; th = $th\n")
        if go
            it = values(accs)
            acc = start(rf, init)
            for x in values(accs)
                acc = combine(rf, acc, x)
            end
            on_preview(complete(rf, acc))
        end
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
