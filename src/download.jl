function hgf_url_template(repo_id, revision, filename)
    global ENDPOINT
    return "$(ENDPOINT[])/$(repo_id)/resolve/$(escape_uri(revision))/$(escape_uri(filename; safe = "/"))"
end

abstract type REPO end
struct DATASET_REPO <: REPO end
struct SPACE_REPO <: REPO end

const REPO_TYPE = Union{REPO, Nothing}

joinurlpath(args...) = join(Iterators.map(Base.Fix2(strip, '/'), args), '/')

is_valid_repo(::REPO_TYPE) = true
is_valid_repo(_) = false

repo_from_string(t::REPO_TYPE) = t
function repo_from_string(s::AbstractString)
    s in ("model", "models") && return nothing
    s in ("dataset", "datasets") && return DATASET_REPO()
    s in ("space", "spaces") && return SPACE_REPO()
    error("Unknown repo type: $s")
end

repo_string(::DATASET_REPO) = "datasets"
repo_string(::SPACE_REPO) = "spaces"

repo_type_name(::Nothing) = "model"
repo_type_name(::DATASET_REPO) = "dataset"
repo_type_name(::SPACE_REPO) = "space"

build_repo(repo_type::REPO, repo_id) = joinurlpath(repo_string(repo_type), repo_id)
build_repo(::Nothing, repo_id) = repo_id

"""
    HuggingFaceURL(repo_id, [subfolder], filename;
                   repo_type = nothing,
                   revision = "main")

Construct the real url with the inputs. `repo_type` is `nothing` (model), `"dataset"`, or `"space"`.
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
        if isnothing(repo_type)
            for type in (DATASET_REPO(), SPACE_REPO())
                prefix = repo_string(type) * '/'
                if startswith(repo_id, prefix)
                    repo_id, repo_type = chopprefix(repo_id, prefix), type
                    break
                end
            end
        end
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

struct FileMetadata
    commit_hash :: String
    etag        :: String
    location    :: String
    size        :: Union{Int, Nothing}
end

normalize_etag(etag) = strip(chopprefix(etag, "W/"), '"')

url_host(url) = (m = match(r"^[a-z]+://([^/]+)"i, url); isnothing(m) ? nothing : lowercase(m[1]))

"""
    get_file_metadata(url; timeout = 10, headers = [])

Fetch the commit hash, ETag, download location and size of a file on the Hub without downloading it.
"""
get_file_metadata(hgfurl::HuggingFaceURL; kws...) = get_file_metadata(string(hgfurl); kws...)
function get_file_metadata(
    url;
    timeout :: Real = 10,
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
)
    headers = vcat(collect(Pair{String,String}, headers), "accept-encoding" => "identity")
    resp = request_noredir(url; method="HEAD", timeout, headers)
    # follow redirects on the Hub (e.g. renamed repos), but not to the CDN
    for _ in 1:20
        300 <= resp.status < 400 || break
        location = get_header(resp, "location")
        isnothing(location) && break
        startswith(location, '/') && (location = string(match(r"^[a-z]+://[^/]+"i, url).match, location))
        url_host(location) == url_host(url) || break
        url = location
        resp = request_noredir(url; method="HEAD", timeout, headers)
    end
    resp.status >= 400 && status_error_w_ecode(resp)
    commit_hash = get_header(resp, "x-repo-commit")
    etag = something(get_header(resp, "x-linked-etag"), get_header(resp, "etag"), Some(nothing))
    isnothing(commit_hash) && error("Distant resource does not seem to be on the Hugging Face Hub (no commit hash).")
    isnothing(etag) && error("Distant resource does not have an ETag, we won't be able to reliably ensure reproducibility.")
    location = something(get_header(resp, "location"), url)
    size = something(get_header(resp, "x-linked-size"), resp.status == 200 ? get_header(resp, "content-length") : nothing, Some(nothing))
    return FileMetadata(commit_hash, normalize_etag(etag), location, isnothing(size) ? nothing : parse(Int, size))
end

get_etag(url; kws...) = get_file_metadata(url; kws...).etag

hgf_download(
    hgfurl :: HuggingFaceURL, dest :: AbstractString;
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
    verbose :: Bool = false, io :: IO = stderr
) =
    hgf_download(string(hgfurl), dest; name = id(hgfurl), headers, verbose, io)

function hgf_download(
    url :: AbstractString, dest :: AbstractString;
    name :: AbstractString = "",
    headers :: Union{AbstractVector, AbstractDict} = Pair{String,String}[],
    verbose :: Bool = false,
    io :: IO = stderr,
)
    fancy = verbose && io isa Base.TTY && get(ENV, "CI", "") != "true"
    bar = Ref{Union{Progress, Nothing}}(nothing)
    progress = (total, now) -> begin
        total > 0 || return
        isnothing(bar[]) && (bar[] = Progress(total; desc = "Downloading $name ", output = io, showspeed = true))
        update!(bar[], now)
    end
    try
        return Downloads.download(url, dest; headers = with_user_agent(headers), progress = fancy ? progress : nothing)
    finally
        isnothing(bar[]) || finish!(bar[])
    end
end

repo_folder_name(repo_type, repo_id) = string(repo_type_name(repo_type), "s--", replace(repo_id, '/' => "--"))
repo_folder_name(hgfurl::HuggingFaceURL) = repo_folder_name(hgfurl.repo_type, hgfurl.repo_id)

storage_folder(hgfurl::HuggingFaceURL; cache_dir = hf_hub_cache()) = joinpath(cache_dir, repo_folder_name(hgfurl))

snapshot_path(storage, commit_hash, filename) = joinpath(storage, "snapshots", commit_hash, split(filename, '/')...)

is_commit_hash(revision) = occursin(r"^[0-9a-f]{40}$", revision)

function check_relative_path(path, what)
    parts = split(path, ['/', '\\'])
    (isempty(path) || isabspath(path) || any(p -> isempty(p) || p == "..", parts)) &&
        error("Invalid $what: $(repr(path))")
    return path
end

const CACHEDIR_TAG = """
    Signature: 8a477f597d28d172789f06886806bc55
    # This file is a cache directory tag created by huggingface_hub.
    # For information about cache directory tags, see:
    #\thttps://bford.info/cachedir/
    """

function write_cachedir_tag(cache_dir)
    tag = joinpath(cache_dir, "CACHEDIR.TAG")
    isfile(tag) || write(tag, CACHEDIR_TAG)
    return
end

function write_ref(storage, revision, commit_hash)
    ref = joinpath(storage, "refs", split(revision, '/')...)
    isfile(ref) && read(ref, String) == commit_hash && return
    mkpath(dirname(ref))
    write(ref, commit_hash)
    return
end

function resolve_commit(storage, revision)
    ref = joinpath(storage, "refs", split(revision, '/')...)
    return isfile(ref) ? strip(read(ref, String)) : revision
end

function create_pointer(blob, pointer)
    mkpath(dirname(pointer))
    islink(pointer) && rm(pointer)
    try
        symlink(relpath(blob, dirname(pointer)), pointer)
    catch e
        e isa Base.IOError || rethrow()
        cp(blob, pointer; force = true)
    end
    return pointer
end

"""
    try_to_load_from_cache(hgfurl::HuggingFaceURL; cache_dir = hf_hub_cache())

Return the path of the cached file for `hgfurl`, or `nothing` if it is not in the cache. No request is made.
"""
function try_to_load_from_cache(hgfurl::HuggingFaceURL; cache_dir = hf_hub_cache())
    storage = storage_folder(hgfurl; cache_dir)
    pointer = snapshot_path(storage, resolve_commit(storage, hgfurl.revision), hgfurl.filename)
    return isfile(pointer) ? pointer : nothing
end

"""
    cached_download(
        hgfurl :: HuggingFaceURL;
        local_files_only :: Bool = HuggingFaceApi.offline_mode(),
        auth_token :: Union{AbstractString, Nothing} = get_token(),
        cache_dir = HuggingFaceApi.hf_hub_cache(),
    )

Find the local cache of given url or do downloading. If `local_files_only` is set (the default when the
 `HF_HUB_OFFLINE` environment variable is set), it will try to find the file from cache, and error out when not
 found. For downloading from private repo, `auth_token` need to be set, or do `HuggingFaceApi.login()` beforehand.

The cache uses the same layout as the Python `huggingface_hub` library, so files are shared between the two.

See also: [`HuggingFaceURL`](@ref), [`login`](@ref), [`hf_hub_cache`](@ref)
"""
function cached_download(
    hgfurl :: HuggingFaceURL;
    local_files_only :: Bool = offline_mode(),
    auth_token :: Union{AbstractString, Nothing} = get_token(),
    cache_dir :: AbstractString = hf_hub_cache(),
)
    check_relative_path(hgfurl.filename, "filename")
    check_relative_path(hgfurl.revision, "revision")
    storage = storage_folder(hgfurl; cache_dir)
    if is_commit_hash(hgfurl.revision)
        pointer = snapshot_path(storage, hgfurl.revision, hgfurl.filename)
        isfile(pointer) && return pointer
    end

    if local_files_only
        pointer = try_to_load_from_cache(hgfurl; cache_dir)
        isnothing(pointer) && error("Cannot find $(id(hgfurl)) at revision $(hgfurl.revision) in the cache and `local_files_only` is set to true.")
        return pointer
    end

    headers = auth_header(auth_token)
    metadata = try
        get_file_metadata(hgfurl; headers)
    catch e
        e isa Downloads.RequestError || rethrow()
        pointer = try_to_load_from_cache(hgfurl; cache_dir)
        isnothing(pointer) && rethrow()
        @warn "Cannot reach the Hub, using the cached version of $(id(hgfurl))." exception=e
        return pointer
    end

    pointer = snapshot_path(storage, metadata.commit_hash, hgfurl.filename)
    mkpath(dirname(pointer))
    write_cachedir_tag(cache_dir)
    hgfurl.revision == metadata.commit_hash || write_ref(storage, hgfurl.revision, metadata.commit_hash)
    isfile(pointer) && return pointer

    blob = joinpath(storage, "blobs", metadata.etag)
    if !isfile(blob)
        mkpath(dirname(blob))
        incomplete = tempname(dirname(blob); cleanup = false) * ".incomplete"
        try
            # do not send the token to the CDN
            same_host = url_host(metadata.location) == url_host(string(hgfurl))
            hgf_download(metadata.location, incomplete; name = id(hgfurl),
                         headers = same_host ? headers : Pair{String,String}[], verbose = true)
            if !isnothing(metadata.size) && filesize(incomplete) != metadata.size
                error("Downloaded $(filesize(incomplete)) bytes for $(id(hgfurl)), expected $(metadata.size).")
            end
            mv(incomplete, blob; force = true)
        finally
            rm(incomplete; force = true)
        end
    end
    return create_pointer(blob, pointer)
end

relative_file(root, path) = join(splitpath(relpath(path, root)), '/')

function snapshot_files(snapshot)
    files = String[]
    for (root, _, fs) in walkdir(snapshot), f in fs
        push!(files, relative_file(snapshot, joinpath(root, f)))
    end
    return sort!(files)
end

function read_refs(storage)
    refs = Dict{String, Vector{String}}()
    refs_dir = joinpath(storage, "refs")
    isdir(refs_dir) || return refs
    for (root, _, fs) in walkdir(refs_dir), f in fs
        path = joinpath(root, f)
        push!(get!(() -> String[], refs, strip(read(path, String))), relative_file(refs_dir, path))
    end
    return refs
end

"""
    list_cache(; cache_dir = HuggingFaceApi.hf_hub_cache())

Get the list of all the cache, as `repo type => repo id => revision => files`. A revision is a reference
 (like `"main"`) when one points to the snapshot, otherwise a commit hash.
"""
function list_cache(; cache_dir = hf_hub_cache())
    cache_list = Dict{String, Dict{String, Dict{String, Vector{String}}}}()
    isdir(cache_dir) || return cache_list
    for folder in readdir(cache_dir)
        m = match(r"^(model|dataset|space)s--(.+)$", folder)
        isnothing(m) && continue
        storage = joinpath(cache_dir, folder)
        snapshots = joinpath(storage, "snapshots")
        isdir(snapshots) || continue
        refs = read_refs(storage)
        revisions = Dict{String, Vector{String}}()
        for commit_hash in readdir(snapshots)
            files = snapshot_files(joinpath(snapshots, commit_hash))
            for revision in get(refs, commit_hash, [commit_hash])
                revisions[revision] = files
            end
        end
        repos = get!(() -> Dict{String, Dict{String, Vector{String}}}(), cache_list, m[1])
        repos[replace(m[2], "--" => "/")] = revisions
    end
    return cache_list
end

# Delete the blobs no snapshot links to anymore, then empty snapshots and the refs pointing to them.
function cleanup_storage(storage)
    snapshots = joinpath(storage, "snapshots")
    used = Set{String}()
    if isdir(snapshots)
        for (root, _, fs) in walkdir(snapshots; topdown = false)
            for f in fs
                path = joinpath(root, f)
                islink(path) && push!(used, basename(readlink(path)))
            end
            root != snapshots && isempty(readdir(root)) && rm(root)
        end
    end
    blobs = joinpath(storage, "blobs")
    if isdir(blobs)
        for blob in readdir(blobs)
            endswith(blob, ".incomplete") || blob in used || rm(joinpath(blobs, blob))
        end
    end
    remaining = isdir(snapshots) ? Set(readdir(snapshots)) : Set{String}()
    for (commit_hash, names) in read_refs(storage), name in names
        commit_hash in remaining || rm(joinpath(storage, "refs", split(name, '/')...))
    end
    if isempty(remaining)
        rm(storage; recursive = true)
        rm(joinpath(dirname(storage), ".locks", basename(storage)); recursive = true, force = true)
    end
    return
end

"""
    remove_cache(hgfurl::HuggingFaceURL; cache_dir = HuggingFaceApi.hf_hub_cache())

Remove the cached file of the given url, and its blob if no other revision uses it.
"""
function remove_cache(hgfurl::HuggingFaceURL; cache_dir = hf_hub_cache())
    storage = storage_folder(hgfurl; cache_dir)
    isdir(storage) || return
    pointer = snapshot_path(storage, resolve_commit(storage, hgfurl.revision), hgfurl.filename)
    (ispath(pointer) || islink(pointer)) || return
    rm(pointer)
    cleanup_storage(storage)
end

"""
    remove_cache(repo_id::AbstractString; repo_type = nothing, revision = nothing, cache_dir = HuggingFaceApi.hf_hub_cache())

Remove all cached files of a given repo, or only those of `revision` if it is set.
"""
function remove_cache(repo_id::AbstractString; repo_type = nothing, revision = nothing, cache_dir = hf_hub_cache())
    storage = joinpath(cache_dir, repo_folder_name(repo_from_string(repo_type), repo_id))
    isdir(storage) || return
    if isnothing(revision)
        rm(storage; recursive = true)
        rm(joinpath(cache_dir, ".locks", basename(storage)); recursive = true, force = true)
    else
        rm(joinpath(storage, "snapshots", resolve_commit(storage, revision)); recursive = true, force = true)
        cleanup_storage(storage)
    end
end

"""
    hf_hub_download(
        repo_id :: AbstractString,
        filename :: AbstractString;
        repo_type = nothing,
        revision = "main",
        auth_token :: Union{AbstractString, Nothing} = get_token(),
        local_files_only :: Bool  = HuggingFaceApi.offline_mode(),
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
    local_files_only :: Bool  = offline_mode(),
    cache :: Bool = true,
)
    hgfurl = HuggingFaceURL(repo_id, filename; repo_type, revision)
    cache && return cached_download(hgfurl; auth_token, local_files_only)
    local_files_only && error("cannot set cache = false when local_files_only = true.")
    return hgf_download(hgfurl, tempname(); headers = auth_header(auth_token), verbose = true)
end
