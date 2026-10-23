# HuggingFaceApi.jl NEWS

## v0.2.0

### Breaking

- Downloads are cached with the layout of the Python `huggingface_hub` library, in `HuggingFaceApi.hf_hub_cache()`
  (`~/.cache/huggingface/hub` by default), and shared with it. Files cached by v0.1 are not reused; to free their
  space, run `HuggingFaceApi.remove_cache(; now = true)` with v0.1 before upgrading.
- `login` takes a [user access token](https://huggingface.co/settings/tokens) instead of a username and password,
  which the Hub no longer accepts. The token is saved to `$HF_HOME/token`, shared with `hf auth login`.
  `logout()` takes no argument and only removes the saved token.
- API results are parsed with JSON.jl 1.x instead of the deprecated JSON3.jl: objects are `JSON.Object{String, Any}`
  with `String` keys (`haskey(m, "tags")`, not `haskey(m, :tags)`; `m.tags` still works) and arrays are `Vector{Any}`.
- `remove_cache` deletes files immediately and no longer takes `now`. `remove_cache(repo_id)` removes all
  revisions unless `revision` is given. `remove_cache()` without arguments is removed, as the cache is shared.
- `list_cache()` is keyed by `"model"`, `"dataset"` and `"space"`.
- Julia 1.10 or later is required.

### New

- `HF_HOME`, `HF_HUB_CACHE`, `HF_TOKEN`, `HF_TOKEN_PATH`, `HF_ENDPOINT` and `HF_HUB_OFFLINE` environment variables.
- When the Hub cannot be reached, cached files are used.
- `try_to_load_from_cache`, `get_file_metadata`, `hf_home`, `hf_hub_cache`.
- `list_models`, `list_datasets` and `list_spaces` follow pagination up to `limit`.
- `repo_type` accepts `"model"`, `"dataset"`, `"space"` and their plurals (`"spaces"` used to throw).
  `HuggingFaceURL("datasets/user/name", file)` is a dataset URL.
- Filenames, revisions and query parameters are URL-escaped.
- Dependencies: JSON3, OhMyArtifacts, LibGit2, Pkg, SHA and Dates are replaced by JSON and ProgressMeter.
