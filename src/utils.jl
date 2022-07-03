_list_param(p::Union{Nothing, AbstractString}) = p
_list_param(p) = join(p, ',')

_param(p) = "$(p[1])=$(p[2])"
build_query(params) = "?$(join(Iterators.map(_param, params), '&'))"

function request_body(url; kwargs...)
    resp = nothing
    body = sprint() do output
        resp = request(url; output=output, kwargs...)
    end
    return resp, body
end

function status_error(resp, log=nothing)
    logs = !isnothing(log) ? ": $log" : ""
    error("request status $(resp.message)$logs")
end

function get_header(resp, _keys...)
    ks = lowercase.(_keys)
    for (_key, value) in resp.headers
        key = lowercase(_key)
        if any(==(key), ks)
            return value
        end
    end
    return nothing
end

function status_error_w_ecode(resp)
    error_code = get_header(resp, "x-error-code")
    if isnothing(error_code) && resp.status == 401
        error_code = "RepoNotFound"
    end
    status_error(resp, error_code)
end

function _set_easy_noredir(easy, info)
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_MAXREDIRS, 0)
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_FOLLOWLOCATION, false)
end

function request_noredir(url; kwargs...)
    downloader = Downloads.Downloader()
    downloader.easy_hook = _set_easy_noredir
    resp = request(url; downloader = downloader, kwargs...)
    return resp
end
