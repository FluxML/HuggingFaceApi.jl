function request_with_id_error(api, headers = nothing)
    endpoint = get_endpoint()
    resp, body = if isnothing(headers)
        request_body("$(endpoint)/api/$api"; method = "GET")
    else
        request_body("$(endpoint)/api/$api"; method = "GET", headers = headers)
    end

    if resp.status >= 400
        request_id = get_header(resp, "x-request-id")
        log = isnothing(request_id) ? nothing : "request id = $request_id"
        status_error(resp, log)
    else
        return JSON3.read(body)
    end
end

# HfApi

"""
    login(user::AbstractString = readline())

Login to huggingface hub and get/save the account token for operations that need authentication.
 Re-run this function with username (i.e. `login(username)`) if token expired.
"""
login(user::AbstractString) = login(maybe_login_prompt(user))
function login(userpass::LibGit2.UserPasswordCredential = login_prompt())
    endpoint = get_endpoint()
    resp, body = withbuf(LoginBuffer(userpass)) do input
        request_body("$(endpoint)/api/login"; method="POST", input=input,
                     headers = ["content-type" => "application/json"])
    end

    if resp.status == 200
        resp_body = JSON3.read(body)
        write_cred(userpass)
        Base.shred!(userpass)
        token = resp_body.token
        save_token(token)
        return token
    else
        Base.shred!(userpass)
        status_error(resp, "$body")
    end
end

function whoami(token = get_token())
    ensure_token(token)
    endpoint = get_endpoint()
    resp, body = request_body("$(endpoint)/api/whoami-v2"; method="GET", headers = auth_header(token))

    if resp.status >= 400
        status_error(resp, "Invalid user token. Make sure you login or pass a correct token.")
    else
        return JSON3.read(body)
    end
end

"""
    logout()

Logout from huggingface hub and remove all authentication cache.
"""
function logout(token = get_token())
    ensure_token(token)
    username = whoami(token).name
    erase_cred(username)

    endpoint = get_endpoint()
    resp = request("$(endpoint)/api/logout"; method="POST", headers = auth_header(token))
    if resp.status >= 400
        status_error(resp)
    else
        delete_token()
    end
end

_get_tags(type) = request_with_id_error("$(type)-tags-by-type")
get_model_tags() = _get_tags("models")
get_dataset_tags() = _get_tags("datasets")

function _info(type, repo_id, revision, token = get_token())
    endpoint = get_endpoint()
    url = "$(endpoint)/api/$(type)/$(repo_id)"
    url = isnothing(revision) ? url : "$(url)/revision/$(revision)"
    url = "$(url)?securityStatus=true"

    resp, body = request_body(url; method = "GET", headers = auth_header(token))
    if resp.status >= 400
        status_error_w_ecode(resp)
    else
        return JSON3.read(body)
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

function _list(type, token; kwargs...)
    isnothing(token) || whoami(token)
    headers = auth_header(token)

    params = Pair[]
    for (k, v) in kwargs
        isnothing(v) || if v isa Bool
            v && push!(params, k=>true)
        else
            push!(params, k=>v)
        end
    end

    api = isempty(params) ? type : "$(type)$(build_query(params))"
    return request_with_id_error(api, headers)
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
 - `sort`: Property to use when sorting, such as downloads or author.
 - `direction`: Direction in which to sort, such as -1 for descending, and anything else for ascending.
 - `limit`: Limit the number of models fetched.
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
 - `filter`: Filter based on tags, such as task_categories:text-classification or languages:en.
 - `sort`: Property to use when sorting, such as downloads or author.
 - `direction`: Direction in which to sort, such as -1 for descending, and anything else for ascending.
 - `limit`: Limit the number of datasets fetched.
 - `full`: Whether to fetch most dataset data, such as all tags, the files, etc.
 - `cardData`: Whether to grab the metadata for the dataset as well. Can contain useful information such as the PapersWithCode ID.
"""
function list_datasets(token = get_token();
                       search = nothing, author = nothing, filter = nothing,
                       sort = nothing, direction = nothing, limit = nothing,
                       full::Bool = false, cardData::Bool = false)

    filter = _list_param(filter)
    _list("datasets", token; search, author, filter, sort, direction, limit, full, cardData)
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
 - `sort`: Property to use when sorting, such as downloads or author.
 - `direction`: Direction in which to sort, such as -1 for descending, and anything else for ascending.
 - `limit`: Limit the number of models fetched.
 - `full`: Whether to fetch most model data, such as all tags, the files, etc.
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
