function request_with_id_error(api, headers = Pair{String,String}[])
    resp, body = request_body("$(get_endpoint())/api/$api"; method = "GET", headers)
    resp.status >= 400 && id_error(resp)
    return JSON.parse(body)
end

function id_error(resp)
    request_id = get_header(resp, "x-request-id")
    log = isnothing(request_id) ? nothing : "request id = $request_id"
    status_error(resp, log)
end

# HfApi

"""
    login(token = <prompt>)

Validate a [user access token](https://huggingface.co/settings/tokens) and save it to
 [`get_token_path()`](@ref get_token_path) for operations that need authentication.
 The file is shared with the Python `huggingface_hub` library, so `hf auth login` works too.
"""
function login(token::AbstractString)
    token = ensure_token(clean_token(token))
    info = whoami(token)
    save_token(token)
    @info "Logged in as $(info.name), token saved to $(get_token_path())."
    return nothing
end
function login()
    secret = Base.getpass("Hugging Face token")
    try
        return login(read(secret, String))
    finally
        Base.shred!(secret)
    end
end

function whoami(token = get_token())
    ensure_token(token)
    endpoint = get_endpoint()
    resp, body = request_body("$(endpoint)/api/whoami-v2"; method="GET", headers = auth_header(token))

    if resp.status >= 400
        status_error(resp, "Invalid user token. Make sure you login or pass a correct token.")
    else
        return JSON.parse(body)
    end
end

"""
    logout()

Remove the token saved by [`login`](@ref).
"""
function logout()
    delete_token()
    isnothing(clean_token(get(ENV, "HF_TOKEN", ""))) ||
        @warn "The `HF_TOKEN` environment variable is set and will still be used."
    return nothing
end

_get_tags(type) = request_with_id_error("$(type)-tags-by-type")
get_model_tags() = _get_tags("models")
get_dataset_tags() = _get_tags("datasets")

function _info(type, repo_id, revision, token = get_token())
    endpoint = get_endpoint()
    url = "$(endpoint)/api/$(type)/$(repo_id)"
    url = isnothing(revision) ? url : "$(url)/revision/$(escape_uri(revision))"
    url = "$(url)?securityStatus=true"

    resp, body = request_body(url; method = "GET", headers = auth_header(token))
    if resp.status >= 400
        status_error_w_ecode(resp)
    else
        return JSON.parse(body)
    end
end

function list_repo_files(type, repo_id, revision, token = get_token())
    infos = _info(type, repo_id, revision, token)
    return [f.rfilename for f in infos.siblings]
end
list_repo_files(type, repo_id; revision = nothing, token = get_token()) = list_repo_files(type, repo_id, revision, token)
list_repo_files(repo_id; revision = nothing, token = get_token()) = list_repo_files("models", repo_id, revision, token)

for type in (:model, :dataset, :space)
    type_s = "$(type)s"
    type_info = Symbol(type, :_info)
    list_type_files = Symbol(:list_, type, :_files)

    type_info_doc =
        """
            $type_info(repo_id; revision = nothing, token = get_token())

        Get information for a specific $type repo `repo_id`.
        """

    list_type_files_doc =
        """
            $list_type_files(repo_id; revision = nothing, token = get_token())

        List all files in the specific $type repo `repo_id`.
        """

    @eval begin
        $type_info(repo_id, revision, token = get_token()) = _info($type_s, repo_id, revision, token)
        $type_info(repo_id; revision = nothing, token = get_token()) =
            $type_info(repo_id, revision, token)
        $list_type_files(repo_id, revision, token = get_token()) =
            list_repo_files($type_s, repo_id, revision, token)
        $list_type_files(repo_id; revision = nothing, token = get_token()) =
            $list_type_files(repo_id, revision, token)

        Core.@doc $type_info_doc
        $type_info

        Core.@doc $list_type_files_doc
        $list_type_files
    end
end

function _list(type, token; limit = nothing, kwargs...)
    headers = auth_header(token)

    params = Pair[]
    for (k, v) in pairs((; limit, kwargs...))
        isnothing(v) || if v isa Bool
            v && push!(params, k=>true)
        else
            push!(params, k=>v)
        end
    end

    url = "$(get_endpoint())/api/$(type)"
    isempty(params) || (url *= build_query(params))
    results = Any[]
    while true
        resp, body = request_body(url; method = "GET", headers)
        resp.status >= 400 && id_error(resp)
        append!(results, JSON.parse(body))
        url = next_page(resp)
        (isnothing(url) || isnothing(limit) || length(results) >= limit) && break
    end
    isnothing(limit) || length(results) <= limit || resize!(results, limit)
    return results
end

"""
    list_models(token = get_token();
                search = nothing, author = nothing, filter = nothing,
                sort = nothing, direction = nothing, limit = nothing,
                full::Bool = !isnothing(filter), cardData::Bool = false)

Get information from all models in the Hub. You can specify additional parameters to have more specific results.
 - `search`: Filter based on substrings for repos and their usernames, such as resnet or microsoft
 - `author`: Filter models by an author or organization, such as huggingface or microsoft
 - `filter`: Filter based on tags, such as text-classification or spacy.
 - `sort`: Property to use when sorting, such as `downloads`, `likes`, `lastModified`, `createdAt` or `trendingScore`.
 - `direction`: Direction in which to sort. Results are sorted in descending order; the Hub only accepts
   ascending order (`1`) for `createdAt`.
 - `limit`: Limit the number of models fetched. Results come in pages of at most 1000; without `limit`, only the first page is returned.
 - `full`: Whether to fetch most model data, such as all tags, the files, etc.
 - `cardData`: Whether to grab the metadata for the model as well, such as carbon emissions, metrics, and datasets trained on.
"""
function list_models(token = get_token();
                     search = nothing, author = nothing, filter = nothing,
                     sort = nothing, direction = nothing, limit = nothing,
                     full::Bool = !isnothing(filter), cardData::Bool = false, config::Bool = false)

    filter = _list_param(filter)
    _list("models", token; search, author, filter, sort, direction, limit, full, cardData, config)
end

"""
    list_datasets(token = get_token();
                  search = nothing, author = nothing, filter = nothing,
                  sort = nothing, direction = nothing, limit = nothing,
                  full::Bool = false, cardData::Bool = false)

Get information from all datasets in the Hub. You can specify additional parameters to have more specific results.
 - `search`: Filter based on substrings for repos and their usernames, such as pets or microsoft
 - `author`: Filter datasets by an other or organization, such as huggingface or microsoft
 - `filter`: Filter based on tags, such as task_categories:text-classification or language:en.
 - `sort`: Property to use when sorting, such as `downloads`, `likes`, `lastModified`, `createdAt` or `trendingScore`.
 - `direction`: Direction in which to sort. Results are sorted in descending order; the Hub only accepts
   ascending order (`1`) for `createdAt`.
 - `limit`: Limit the number of datasets fetched. Results come in pages of at most 1000; without `limit`, only the first page is returned.
 - `full`: Whether to fetch most dataset data, such as all tags, the files, etc.
 - `cardData`: Whether to grab the metadata for the dataset as well. Can contain useful information such as the PapersWithCode ID.
"""
function list_datasets(token = get_token();
                       search = nothing, author = nothing, filter = nothing,
                       sort = nothing, direction = nothing, limit = nothing,
                       cardData::Bool = false, full::Bool = cardData)

    filter = _list_param(filter)
    _list("datasets", token; search, author, filter, sort, direction, limit, full)
end

"""
    list_spaces(token = get_token();
               search = nothing, author = nothing, filter = nothing,
               datasets = nothing, models = nothing, linked::Bool = false,
               sort = nothing, direction = nothing, limit = nothing,
               full::Bool = false)

Get information from all Spaces in the Hub. You can specify additional parameters to have more specific results.
 - `search`: Filter based on substrings for repos and their usernames, such as resnet or microsoft
 - `author`: Filter models by an author or organization, such as huggingface or microsoft
 - `filter`: Filter based on tags, such as text-classification or spacy.
 - `sort`: Property to use when sorting, such as `downloads`, `likes`, `lastModified`, `createdAt` or `trendingScore`.
 - `direction`: Direction in which to sort. Results are sorted in descending order; the Hub only accepts
   ascending order (`1`) for `createdAt`.
 - `limit`: Limit the number of Spaces fetched. Results come in pages of at most 1000; without `limit`, only the first page is returned.
 - `full`: Whether to fetch most Space data, such as all tags, the files, etc.
 - `datasets`: Whether to return Spaces that make use of a dataset. The name of a specific dataset can be passed as a string.
 - `models`: Whether to return Spaces that make use of a model. The name of a specific model can be passed as a string.
 - `linked`: Whether to return Spaces that make use of either a model or a dataset.
"""
function list_spaces(token = get_token();
                     search = nothing, author = nothing, filter = nothing,
                     datasets = nothing, models = nothing, linked::Bool = false,
                     sort = nothing, direction = nothing, limit = nothing,
                     full::Bool = false)

    filter = _list_param(filter)
    datasets = _list_param(datasets)
    models = _list_param(models)
    _list("spaces", token; search, author, filter, datasets, models, linked, sort, direction, limit, full)
end

"""
    list_metrics()

Get information from all metrics in the Hub.
"""
list_metrics() = request_with_id_error("metrics")
