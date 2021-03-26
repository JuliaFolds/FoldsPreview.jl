module FoldsPreview

export with_distributed_preview, with_threaded_preview, with_preview, IntervalThrottle

using Distributed
using Transducers
using Transducers:
    Executor,
    R_,
    Transducer,
    combine,
    complete,
    inner,
    next,
    start,
    unwrap,
    wrap,
    wrapping,
    xform

include("throttles.jl")
using .Throttles: IntervalThrottle, Throttle

include("core.jl")

end # module FoldsPreview
