function hgf_url_template(repo_id, revision, filename)
    global ENDPOINT
    return "$(ENDPOINT[])/$(repo_id)/resolve/$(revision)/$(filename)"
end

abstract type REPO end
struct DATASET_REPO <: REPO end
struct SPACE_REPO <: REPO end

const REPO_TYPE = Union{REPO, Nothing}

joinurlpath(args...) = join(Iterators.map(Base.Fix2(strip, '/'), args), '/')

is_valid_repo(::REPO_TYPE) = true
is_valid_repo(_) = false

repo_from_string(t::REPO_TYPE) = t
repo_from_string(s::AbstractString) = s == "datasets" ?
    DATASET_REPO() : "spaces" ? SPACE_REPO() : error("Unknown repo type: $s")

repo_string(::DATASET_REPO) = "datasets"
repo_string(::SPACE_REPO) = "spaces"

build_repo(repo_type::REPO, repo_id) = joinurlpath(repo_string(repo_type), repo_id)
build_repo(::Nothing, repo_id) = repo_id

"""
    HuggingFaceURL(repo_id, [subfolder], filename;
                   repo_type = nothing,
                   revision = "main")

Construct the real url with the inputs.
"""
struct HuggingFaceURL
    repo_id   :: String
    filename  :: String
    repo_type :: REPO_TYPE
    revision  :: String

    function HuggingFaceURL(repo_id, filename,
                            repo_type::REPO_TYPE = nothing,
                            revision::AbstractString = "main")
        is_valid_repo(repo_type) || error("Invalid repo type: $repo_type")
        return new(repo_id, filename, repo_type, revision)
    end
end

HuggingFaceURL(
    repo_id, subfolder, filename,
    repo_type::REPO_TYPE = nothing,
    revision::AbstractString = "main"
) =
    HuggingFaceURL(repo_id, joinurlpath(subfolder, filename), repo_type, revision)

HuggingFaceURL(
    repo_id, path...;
    repo_type = nothing,
    revision = "main"
) =
    HuggingFaceURL(repo_id, path..., repo_from_string(repo_type), revision)

repo(hgfurl::HuggingFaceURL) = build_repo(hgfurl.repo_type, hgfurl.repo_id)
id(hgfurl::HuggingFaceURL) = joinurlpath(repo(hgfurl), hgfurl.filename)

Base.string(hgfurl::HuggingFaceURL) = hgf_url_template(repo(hgfurl), hgfurl.revision, hgfurl.filename)
Base.show(io::IO, hgfurl::HuggingFaceURL) = Base.print(io, "HuggingFaceURL(", string(hgfurl), ')')

get_etag(hgfurl::HuggingFaceURL; kws...) = get_etag(string(hgfurl); kws...)
function get_etag(
    url;
    timeout :: Real = 10,
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
)
    resp = request_noredir(url; method="HEAD", timeout, headers)
    resp.status >= 400 && status_error_w_ecode(resp)
    etag = get_header(resp, "etag", "x-linked-etag")
    isnothing(etag) || return strip(etag, '"')
    error("Distant resource does not have an ETag, we won't be able to reliably ensure reproducibility.")
end

url_to_filename(hgfurl::HuggingFaceURL, etag=nothing) = url_to_filename(string(hgfurl), etag)
function url_to_filename(url, etag=nothing)
    buf = IOBuffer(maxsize=150)
    bytes2hex(buf, sha256(url))
    isnothing(etag) || (write(buf, '.'); bytes2hex(buf, sha256(etag)))
    return String(take!(buf))
end

hgf_download(
    hgfurl :: HuggingFaceURL, dest :: AbstractString;
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
    verbose :: Bool = false, io :: IO = Pkg.stdout_f()
) =
    hgf_download(string(hgfurl), dest; name = id(hgfurl), headers, verbose, io)

function hgf_download(
    url :: AbstractString, dest :: AbstractString;
    name :: AbstractString = "",
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
    verbose :: Bool = false,
    io :: IO = Pkg.stdout_f(),
)
    do_fancy = verbose && Pkg.can_fancyprint(io)
    progress =  if do_fancy
        bar = MiniProgressBar(header="Downloading $name", color=Base.info_color())
        start_progress(io, bar)
        (total, now) -> begin
            bar.max = total
            bar.current = now
            show_progress(io, bar)
        end
    else
        (total, now) -> nothing
    end
    try
        Downloads.download(url, dest; headers, progress)
    finally
        do_fancy && end_progress(io, bar)
    end
end

"""
    cached_download(
        hgfurl :: HuggingFaceURL;
        local_files_only :: Bool = false,
        auth_token :: Union{AbstractString, Nothing} = nothing,
    )

Find the local cache of given url or do downloading. If `local_files_only` is set, it will try to
 find the file from cache, and error out when not found. For downloading from private repo,
 `auth_token` need to be set, or do `HuggingFaceApi.login()` beforehand.

See also: [`HuggingFaceURL`](@ref), [`login`](@ref)
"""
function cached_download(
    hgfurl :: HuggingFaceURL;
    local_files_only :: Bool = false,
    auth_token :: Union{AbstractString, Nothing} = get_token(),
)
    # add auth token if provided
    headers = auth_header(auth_token)

    url = string(hgfurl)
    etag = local_files_only ? nothing : get_etag(url; headers)
    name = url_to_filename(url, etag)

    # local file exists
    hash = @my_artifact :hash name
    !isnothing(hash) && my_artifact_exists(hash) && return my_artifact_path(hash)

    # no local file
    local_files_only && error("no cached file found and `local_files_only` is set to true.")

    # download and bind
    hash = @my_artifact :download name hgfurl hgf_download headers verbose=true

    # for future local_files_only, bind name without etag
    @my_artifact :bind split(name, '.')[1] hash force=true

    return my_artifact_path(hash)
end

"""
    remove_cache(hgfurl::HuggingFaceURL; now=false)

Remove files link to the given url. If `now` is set to `true`, cache file will be deleted immediately,
 otherwise waiting `OhMyArtifacts` to do the garbage collection.
"""
function remove_cache(hgfurl::HuggingFaceURL; now=false)
    name = url_to_filename(hgfurl)
    artifacts = OhMyArtifacts.load_my_artifacts_toml(hgf_artifacts())

    for (key, val) in artifacts
        if startswith(key, name)
            @my_artifact :unbind key
        end
    end

    if now
        OhMyArtifacts.find_orphanages(; collect_delay = Dates.Hour(0))
    end
end

"""
    remove_cache(; now=false)

Remove all cached files. If `now` is set to `true`, cache file will be deleted immediately,
 otherwise waiting `OhMyArtifacts` to do the garbage collection.
"""
function remove_cache(; now=false)
    artifacts = OhMyArtifacts.load_my_artifacts_toml(hgf_artifacts())

    for (key, val) in artifacts
        @my_artifact :unbind key
    end

    if now
        OhMyArtifacts.find_orphanages(; collect_delay = Dates.Hour(0))
    end
end

"""
    hf_hub_download(
        repo_id :: AbstractString,
        filename :: AbstractString;
        repo_type = nothing,
        revision = "main",
        auth_token :: Union{AbstractString, Nothing} = get_token(),
        local_files_only :: Bool  = false,
        cache :: Bool = true,
    )

Construct [`HuggingFaceURL`](@ref) and do [`cached_download`](@ref). If `cache` is `false`, download file
 to the temp dir with name generated by `tempname()`. If `local_files_only` is set, `cache` must set.
"""
function hf_hub_download(
    repo_id :: AbstractString,
    filename :: AbstractString;
    repo_type = nothing,
    revision = "main",
    auth_token :: Union{AbstractString, Nothing} = get_token(),
    local_files_only :: Bool  = false,
    cache :: Bool = true,
)
    hgfurl = HuggingFaceURL(repo_id, filename; repo_type, revision)
    cache && return cached_download(hgfurl; auth_token, local_files_only)
    local_files_only && error("cannot set cache = false when local_files_only = true.")
    return hgf_download(hgfurl, tempname(); headers = auth_header(auth_token), verbose = true)
end
