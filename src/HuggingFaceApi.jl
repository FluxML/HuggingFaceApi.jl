module HuggingFaceApi

using SHA
using Pkg
using Pkg.MiniProgressBars
using Downloads
import Dates

using OhMyArtifacts

using JSON3

const my_artifacts = Ref{String}()


const DEFAULT_ENDPOINT = "https://huggingface.co"
const ENDPOINT = Ref(DEFAULT_ENDPOINT)
const token_path = Ref{String}()

const PYTORCH_WEIGHTS_NAME = "pytorch_model.bin"
const CONFIG_NAME = "config.json"

function hgf_dir()
    return dirname(hgf_artifacts())
end

function hgf_artifacts()
    global my_artifacts
    return my_artifacts[]
end

function env_is_true(key)
    e = get(ENV, key, false)
    e isa Bool && return e
    e isa String && return lowercase(e) in ("1", "on", "yes", "true") ? true : false
    return false
end

function __init__()
    global ENDPOINT, my_artifacts, token_path
    # my artifacts
    my_artifacts[] = @my_artifacts_toml!()

    token_path[] = expanduser("~/.huggingface/token")

    # set 🤗 endpoint
    env_is_true("HUGGINGFACE_CO_STAGING") && (ENDPOINT[] = "https://moon-staging.huggingface.co")
    return
end

"add 🤗 autocomplete in REPL"
function huggingface_emoji()
    REPL = Base.require(Base.PkgId(Base.UUID((0x3fa0cd96_eef1_5676, 0x8a61_b3b8758bbffb)), "REPL"))
    if !haskey(REPL.REPLCompletions.emoji_symbols, "\\:huggingface:")
        REPL.REPLCompletions.emoji_symbols["\\:huggingface:"] = "🤗"
    end
    return :🤗
end

function get_endpoint()
    global ENDPOINT
    return ENDPOINT[]
end

function set_endpoint(endpoint)
    global ENDPOINT
    ENDPOINT[] = endpoint
    return ENDPOINT[]
end

function with_endpoint(f, endpoint)
    global ENDPOINT
    old_endpoint = ENDPOINT[]
    try
        ENDPOINT[] = endpoint
        return f()
    finally
        ENDPOINT[] = old_endpoint
    end
end

function get_token_path()
    global token_path
    return abspath(token_path[])
end

export hf_hub_download, HuggingFaceURL, cached_download

include("auth.jl")
include("utils.jl")
include("download.jl")
include("api.jl")

end
