using FLoops
using FoldsPreview
using UnicodePlots

function online_histogram(;
    N = 100_000_000_000,
    interval = 10,
    ex = ThreadedEx(),
    nbins = 1000,
)
    function on_preview(((hist,), (nsamples,)))
    # function on_preview(((hist,), (nsamples,), (tids,)))
        # display(heatmap(log10.(hist .+ 1)))
        display(heatmap(hist))
        @show nsamples
        # @show sort(collect(tids))
    end
    with_preview(on_preview, ex, interval) do previewer
        @floop ex for n in previewer(1:N)
            x = randn() * 0.3 + rand(-1:1)
            y = randn() * 0.3 + rand(-1:1)
            indexfor(v) = floor(Int, (v + 1.5) / 3 * nbins)
            i = indexfor(x)
            j = indexfor(y)
            0 < i <= nbins || continue
            0 < j <= nbins || continue
            sample = (i, j)
            @reduce() do (hist = zeros(Int, nbins, nbins); sample)
                if sample isa Tuple  # sequential case
                    hist[i, j] += 1
                else
                    sample::Matrix{Int}  # otherwise, we are merging
                    hist .+= sample
                end
            end
            @reduce(nsamples = 0 + 1)
            # @reduce  tids = union!(Set{Int}(), Threads.threadid())
        end
        return hist
    end
end
