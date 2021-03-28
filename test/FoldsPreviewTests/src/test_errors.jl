module TestErrors

using Folds
using FoldsPreview
using Test
using Transducers

using ..Utils: @test_error, foreach_executor, print_error

function test_early_error_in_body(ex)
    th = IntervalThrottle(Inf)
    local reach_body::Bool = false
    err = @test_error with_preview(identity, ex, th) do previewer
        reach_body = true
        error("ERROR FROM BODY")
    end
    @test reach_body
    @test any(err) do e
        occursin("ERROR FROM BODY", sprint(showerror, e))
    end
end

function test_early_error_in_body()
    foreach_executor(test_early_error_in_body)
end

function test_early_error_in_on_preview(ex)
    th = IntervalThrottle(-1)
    race = Channel{Symbol}(3) do race
        sleep(60 * 5)
        put!(race, :timeout)
    end
    function on_preview(_)
        put!(race, :reach_on_preview)
        error("ERROR FROM ON_PREVIEW")
    end
    err = @test_error with_preview(on_preview, ex, th) do previewer
        Folds.collect(previewer(1:10), ex)
    end
    put!(race, :done)
    close(race)
    race_result = take!(race)

    @test err isa CompositeException
    if race_result != :reach_on_preview
        print_error(err)
    end

    @test race_result == :reach_on_preview
    @test any(err) do e
        occursin("ERROR FROM ON_PREVIEW", sprint(showerror, e))
    end
end

function test_early_error_in_on_preview()
    foreach_executor(test_early_error_in_on_preview)
end

end  # module
