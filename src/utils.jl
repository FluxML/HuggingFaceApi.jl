_list_param(p::Union{Nothing, AbstractString}) = p
_list_param(p) = join(p, ',')

function escape_uri(s; safe = "")
    io = IOBuffer()
    for b in codeunits(string(s))
        c = Char(b)
        if b < 0x80 && (isletter(c) || isdigit(c) || c in "-_.~" || c in safe)
            write(io, c)
        else
            print(io, '%', uppercase(string(b; base = 16, pad = 2)))
        end
    end
    return String(take!(io))
end

_param(p) = "$(escape_uri(p[1]))=$(escape_uri(p[2]; safe = ","))"
build_query(params) = "?$(join(Iterators.map(_param, params), '&'))"

user_agent() = "HuggingFaceApi.jl/$(pkgversion(@__MODULE__)); julia/$(VERSION)"

function with_user_agent(headers)
    any(h -> lowercase(first(h)) == "user-agent", headers) && return headers
    return vcat(Pair{String,String}["user-agent" => user_agent()], collect(Pair{String,String}, headers))
end

http_request(url; headers = Pair{String,String}[], kwargs...) =
    Downloads.request(url; headers = with_user_agent(headers), kwargs...)

function request_body(url; kwargs...)
    resp = nothing
    body = sprint() do output
        resp = http_request(url; output=output, kwargs...)
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

function next_page(resp)
    link = get_header(resp, "link")
    isnothing(link) && return nothing
    m = match(r"<([^>]+)>\s*;\s*rel=\"next\"", link)
    return isnothing(m) ? nothing : String(m[1])
end

function _set_easy_noredir(easy, info)
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_MAXREDIRS, 0)
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_FOLLOWLOCATION, false)
end

function request_noredir(url; kwargs...)
    downloader = Downloads.Downloader()
    downloader.easy_hook = _set_easy_noredir
    resp = http_request(url; downloader = downloader, kwargs...)
    return resp
end
