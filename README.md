# HuggingFaceApi

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://fluxml.ai/HuggingFaceApi.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://fluxml.ai/HuggingFaceApi.jl/dev)
[![Build Status](https://github.com/FluxML/HuggingFaceApi.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/FluxML/HuggingFaceApi.jl/actions)
[![Coverage](https://codecov.io/gh/FluxML/HuggingFaceApi.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/FluxML/HuggingFaceApi.jl)

Pure Julia client for the [Hugging Face Hub](https://huggingface.co): download files from model, dataset and
Space repos, and search the Hub.

Downloads are cached with the same layout as the Python
[`huggingface_hub`](https://github.com/huggingface/huggingface_hub) library (`~/.cache/huggingface/hub` by default),
so files already downloaded from Python are reused, and vice versa.

# Example

## Basic usage

```julia
julia> using HuggingFaceApi

julia> file = hf_hub_download("lysandre/arxiv-nlp", "config.json")
"/home/user/.cache/huggingface/hub/models--lysandre--arxiv-nlp/snapshots/b6b7a3a5bd5ad9a8c1e0e3e54b6ba6e0f2b1ad4b/config.json"

# or equivalent to
julia> url = HuggingFaceURL("lysandre/arxiv-nlp", "config.json")
HuggingFaceURL(https://huggingface.co/lysandre/arxiv-nlp/resolve/main/config.json)

julia> file = cached_download(url);

# datasets and Spaces, at a pinned revision
julia> hf_hub_download("lhoestq/custom_squad", "dev-v1.1.json";
                       repo_type = "dataset", revision = "e25d55a1c4933f987c46cc75d8ffadd67f257c61");

julia> HuggingFaceApi.list_cache()
Dict{String, Dict{String, Dict{String, Vector{String}}}} with 2 entries:
  "model"   => Dict("lysandre/arxiv-nlp"=>Dict("main"=>["config.json"]))
  "dataset" => Dict("lhoestq/custom_squad"=>Dict("e25d55a1c4933f987c46cc75d8ffadd67f257c61"=>["dev-v1.1.json"]))

# remove cached files when they are no longer needed
julia> HuggingFaceApi.remove_cache(url)

julia> HuggingFaceApi.remove_cache("lhoestq/custom_squad"; repo_type = "dataset")
```

## Download from private repo

Private and gated repos need a [user access token](https://huggingface.co/settings/tokens). Set the `HF_TOKEN`
environment variable, or save the token with `login` (the file is shared with `hf auth login` from Python):

```julia
julia> using HuggingFaceApi

julia> HuggingFaceApi.login()
Hugging Face token:
[ Info: Logged in as chengchingwen, token saved to /home/user/.cache/huggingface/token.

julia> private_file = HuggingFaceApi.hf_hub_download("chengchingwen/test_model_repo", "README.md");

julia> readlines(private_file)
1-element Vector{String}:
 "TEST THIS private repo"

julia> HuggingFaceApi.logout()
```

## Search the hub

Results are [JSON.jl](https://github.com/JuliaIO/JSON.jl) objects, whose fields can be read with `getproperty`:

```julia
julia> models = HuggingFaceApi.list_models(; search = "japanese", filter = ("pytorch", "text-classification"),
                                           sort = "downloads", direction = -1, limit = 3);

julia> [m.id for m in models]
3-element Vector{String}:
 "christian-phu/bert-finetuned-japanese-sentiment"
 "koheiduck/bert-japanese-finetuned-sentiment"
 "jarvisx17/japanese-sentiment-analysis"

julia> models[1].tags
9-element Vector{Any}:
 "transformers"
 "pytorch"
 "bert"
 "text-classification"
 "generated_from_trainer"
 "ja"
 "license:cc-by-sa-4.0"
 "endpoints_compatible"
 "region:us"
```

The Hub returns at most 1000 results per request: pass `limit` to fetch more.

# Configuration

The same environment variables as the Python library are supported:

| Variable         | Default                  | Meaning                                         |
|:-----------------|:-------------------------|:------------------------------------------------|
| `HF_HOME`        | `~/.cache/huggingface`   | Root of the cache and the token file            |
| `HF_HUB_CACHE`   | `$HF_HOME/hub`           | Download cache                                  |
| `HF_TOKEN`       |                          | Access token, used before the saved one         |
| `HF_TOKEN_PATH`  | `$HF_HOME/token`         | File where `login` saves the token              |
| `HF_ENDPOINT`    | `https://huggingface.co` | Hub endpoint, e.g. a mirror                     |
| `HF_HUB_OFFLINE` |                          | Set to `1` to only use cached files             |
