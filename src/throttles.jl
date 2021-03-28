module Throttles

abstract type Throttle end

"""
    IntervalThrottle(interval)

Instruct [`with_preview`](@ref) etc. to call `on_preview` only if the
previous invocation of `on_preview` is at least `interval` seconds ago.
"""
struct IntervalThrottle <: Throttle
    interval::Float64
end

init(::IntervalThrottle) = time_ns()
step(th::IntervalThrottle, prev) =
    if (time_ns() - prev) / 1e9 > th.interval
        (true, time_ns())
    else
        (false, prev)
    end

end # module Throttles
