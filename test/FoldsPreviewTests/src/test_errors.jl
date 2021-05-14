module TestErrors

using Distributed: RemoteChannel
using Folds
using FoldsPreview
using Test
using Transducers

using ..Utils: @test_error, foreach_executor, with_racer, print_error

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
    th = IntervalThrottle(0)
    err = nothing
    ok = with_racer(:reach_on_preview) do win
        function on_preview(_)
            win()
            error("ERROR FROM ON_PREVIEW")
        end
        err = @test_error with_preview(on_preview, ex, th) do previewer
            Folds.collect(previewer(1:10), ex)
        end
    end

    @test err isa CompositeException
    if !ok
        print_error(err)
    end

    @test any(err) do e
        occursin("ERROR FROM ON_PREVIEW", sprint(showerror, e))
    end
end

function test_early_error_in_on_preview()
    foreach_executor(test_early_error_in_on_preview)
end

function test_late_error_in_on_preview(ex)
    counter = Ref(0)
    barrier = if ex isa DistributedEx
        RemoteChannel(() -> Channel{Nothing}())
    else
        Channel{Nothing}()
    end
    err = nothing
    ok = with_racer(:iter1, :iter2, :iter3) do win1, win2, win3
        function on_preview(_)
            i = counter[] += 1
            @debug "`on_preview`: i = $i"
            if i == 1
                win1()
            elseif i == 2
                win2()
            elseif i == 3
                win3()
            else
                put!(barrier, nothing)
                error("ERROR FROM ON_PREVIEW")
            end
        end
        err = @test_error with_preview(on_preview, ex, 0) do previewer
            itr = (
                begin
                    # The first iteration is required for starting `on_preview`.
                    # So, block on the second:
                    x == 2 && take!(barrier)
                    x
                end
                for x in 1:10
            )
            Folds.collect(previewer(itr), ex)
        end
    end

    @test err isa CompositeException
    if !ok
        print_error(err)
    end

    @test any(err) do e
        occursin("ERROR FROM ON_PREVIEW", sprint(showerror, e))
    end
end

function test_late_error_in_on_preview()
    foreach_executor(test_late_error_in_on_preview)
end

end  # module
