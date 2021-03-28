module TestExamples

using Test
using Transducers

using ..Utils: foreach_executor

module OnlineExtrema
include("../../../examples/online_extrema.jl")
end

module OnlineHistogram
include("../../../examples/online_histogram.jl")
end

function test_extrema(ex)
    @test OnlineExtrema.online_extrema(N = 100, ex = ex) isa Any
end

function test_extrema()
    foreach_executor(test_extrema)
end

function test_histogram(ex)
    @test OnlineHistogram.online_histogram(N = 100, ex = ex) isa Any
end

function test_histogram()
    foreach_executor(test_histogram)
end

end  # module
