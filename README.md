# HuggingFaceApi

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://fluxml.ai/HuggingFaceApi.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://fluxml.ai/HuggingFaceApi.jl/dev)
[![Build Status](https://github.com/FluxML/HuggingFaceApi.jl/workflows/CI/badge.svg)](https://github.com/FluxML/HuggingFaceApi.jl/actions)
[![Coverage](https://codecov.io/gh/FluxML/HuggingFaceApi.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/FluxML/HuggingFaceApi.jl)

Pure Julia [Huggingface api](https://github.com/huggingface/huggingface_hub)


# Example

## Basic usage

```julia
julia> using HuggingFaceApi

julia> file = hf_hub_download("lysandre/arxiv-nlp", "config.json");

# or equivalent to
julia> url = HuggingFaceURL("lysandre/arxiv-nlp", "config.json")
HuggingFaceURL(https://huggingface.co/lysandre/arxiv-nlp/resolve/main/config.json)

julia> file = HuggingFaceApi.cached_download(url);

julia> readlines(file)
29-element Vector{String}:
 "{"
 "  \"_num_labels\": 1,"
 "  \"activation_function\": \"gelu_new\","
 "  \"attn_pdrop\": 0.1,"
 ⋮
 "  \"summary_type\": \"token_ids\","
 "  \"summary_use_proj\": true,"
 "  \"vocab_size\": 50257"
 "}"

# remove cached file if don't need it anymore
julia> HuggingFaceApi.remove_cache(url; now=true)
[ Info: 1 MyArtifact deleted (604.000 byte)


```

## Download from private repo

```julia
julia> using HuggingFaceApi

julia> HuggingFaceApi.login("chengchingwen");
password: 

julia> private_file = HuggingFaceApi.hf_hub_download("chengchingwen/test_model_repo", "README.md");

julia> readlines(private_file)
1-element Vector{String}:
 "TEST THIS private repo"

julia> HuggingFaceApi.logout()

```

## Search the hub

```julia
julia> HuggingFaceApi.list_models(; search = "japanese", filter = ("pytorch", "text-classification"), full=false, limit=5)

5-element JSON3.Array{JSON3.Object, Base.CodeUnits{UInt8, String}, Vector{UInt64}}:
 {
             "id": "daigo/bert-base-japanese-sentiment",
        "private": false,
   "pipeline_tag": "text-classification",
        "modelId": "daigo/bert-base-japanese-sentiment"
}
 {
             "id": "abhishek/autonlp-japanese-sentiment-59363",
        "private": false,
   "pipeline_tag": "text-classification",
        "modelId": "abhishek/autonlp-japanese-sentiment-59363"
}
 {
             "id": "laboro-ai/distilbert-base-japanese-finetuned-livedoor",
        "private": false,
   "pipeline_tag": "text-classification",
        "modelId": "laboro-ai/distilbert-base-japanese-finetuned-livedoor"
}
 {
             "id": "ptaszynski/yacis-electra-small-japanese-cyberbullying",
        "private": false,
   "pipeline_tag": "text-classification",
        "modelId": "ptaszynski/yacis-electra-small-japanese-cyberbullying"
}
 {
             "id": "lewtun/bert-base-japanese-char-v2-finetuned-amazon-jap",
        "private": false,
   "pipeline_tag": "text-classification",
        "modelId": "lewtun/bert-base-japanese-char-v2-finetuned-amazon-jap"
}

```
