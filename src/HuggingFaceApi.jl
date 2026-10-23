module HuggingFaceApi

using Downloads
using JSON
using ProgressMeter: Progress, update!, finish!

const DEFAULT_ENDPOINT = "https://huggingface.co"
const STAGING_ENDPOINT = "https://hub-ci.huggingface.co"
const ENDPOINT = Ref(DEFAULT_ENDPOINT)

const PYTORCH_WEIGHTS_NAME = "pytorch_model.bin"
const CONFIG_NAME = "config.json"

function env_is_true(key)
    e = get(ENV, key, false)
    e isa Bool && return e
    e isa String && return lowercase(e) in ("1", "on", "yes", "true") ? true : false
    return false
end

# Empty environment variables are treated as unset.
function getenv(key, default)
    value = get(ENV, key, "")
    return isempty(value) ? default : value
end

function __init__()
    ENDPOINT[] = rstrip(getenv("HF_ENDPOINT", DEFAULT_ENDPOINT), '/')
    env_is_true("HUGGINGFACE_CO_STAGING") && (ENDPOINT[] = STAGING_ENDPOINT)
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

"""
    hf_home()

Root directory of the Hugging Face files shared with the Python `huggingface_hub` library:
`\$HF_HOME`, or `\$XDG_CACHE_HOME/huggingface`, or `~/.cache/huggingface`.
"""
hf_home() = expanduser(getenv("HF_HOME", joinpath(getenv("XDG_CACHE_HOME", joinpath(homedir(), ".cache")), "huggingface")))

"""
    hf_hub_cache()

Directory of the download cache: `\$HF_HUB_CACHE`, or `\$(hf_home())/hub`.
"""
hf_hub_cache() = expanduser(getenv("HF_HUB_CACHE", getenv("HUGGINGFACE_HUB_CACHE", joinpath(hf_home(), "hub"))))

"""
    get_token_path()

File where [`login`](@ref) saves the token: `\$HF_TOKEN_PATH`, or `\$(hf_home())/token`.
"""
get_token_path() = abspath(expanduser(getenv("HF_TOKEN_PATH", joinpath(hf_home(), "token"))))

offline_mode() = lowercase(getenv("HF_HUB_OFFLINE", get(ENV, "TRANSFORMERS_OFFLINE", ""))) in ("1", "on", "yes", "true")

export hf_hub_download, HuggingFaceURL, cached_download

include("auth.jl")
include("utils.jl")
include("download.jl")
include("api.jl")

end
