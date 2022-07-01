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
