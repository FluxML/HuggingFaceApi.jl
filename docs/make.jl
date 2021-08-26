using HuggingFaceApi
using Documenter

DocMeta.setdocmeta!(HuggingFaceApi, :DocTestSetup, :(using HuggingFaceApi); recursive=true)

makedocs(;
    modules=[HuggingFaceApi],
    authors="chengchingwen <adgjl5645@hotmail.com> and contributors",
    repo="https://github.com/chengchingwen/HuggingFaceApi.jl/blob/{commit}{path}#{line}",
    sitename="HuggingFaceApi.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chengchingwen.github.io/HuggingFaceApi.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chengchingwen/HuggingFaceApi.jl",
)
