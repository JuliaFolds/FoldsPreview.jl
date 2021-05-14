using Folds
using FoldsPreview
using UnicodePlots

function online_extrema(;
    N = 100_000_000_000,
    interval = 10,
    ex = ThreadedEx(),
)
    vmin_trace = Float64[]
    vmax_trace = Float64[]
    t_trace = Float64[]
    t0 = time()
    function on_preview((vmin, vmax))
        push!(vmin_trace, -vmin)
        push!(vmax_trace, vmax)
        push!(t_trace, time() - t0)
        rows, columns = displaysize(stdout)
        opts = (height = max(5, rows ÷ 2 - 5), width = max(5, columns - 40))
        xs = log10.(t_trace)
        ylim = (
            floor(min(vmin_trace[1], vmax_trace[1]); digits = 3),
            ceil(max(-vmin, vmax); digits = 3),
        )
        plt1 = lineplot(xs, vmax_trace; ylabel = "extrema", ylim = ylim, opts...)
        lineplot!(plt1, xs, vmin_trace)
        plt2 = lineplot(
            xs,
            log10.(abs.(vmax_trace .- vmin_trace));
            ylabel = "log10(diff)",
            opts...,
        )
        display(plt1)
        display(plt2)
    end
    with_preview(on_preview, ex, interval) do previewer
        Folds.extrema(previewer(1:N), ex) do _
            randn()
        end
    end
end
