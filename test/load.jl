try
    using FoldsPreviewTests
    true
catch
    false
end || begin
    push!(LOAD_PATH, @__DIR__)
    using FoldsPreviewTests
end
