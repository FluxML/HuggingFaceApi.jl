auth_pair(auth_token) = "authorization"=>"Bearer $auth_token"
auth_header(auth_token) = [auth_pair(auth_token)]
auth_header!(headers, auth_token) = push!(headers, auth_pair(auth_token))
auth_pair(::Nothing) = nothing
auth_header(::Nothing) = Pair{String,String}[]
auth_header!(headers, ::Nothing) = headers

ensure_token(::Nothing) = error("No token provided and no saved token found. Set `HF_TOKEN` or run `HuggingFaceApi.login()`.")
ensure_token(token) = token

clean_token(token) = (token = strip(token); isempty(token) ? nothing : String(token))

"""
    get_token()

Get the user access token, from the `HF_TOKEN` environment variable or the file saved by [`login`](@ref)
 (see [`get_token_path`](@ref)). Returns `nothing` if no token is found.
"""
function get_token()
    for key in ("HF_TOKEN", "HUGGING_FACE_HUB_TOKEN")
        token = clean_token(get(ENV, key, ""))
        isnothing(token) || return token
    end
    path = get_token_path()
    return isfile(path) ? clean_token(read(path, String)) : nothing
end

"""
    save_token(token)

Write token to the disk for future use.
"""
function save_token(token)
    path = get_token_path()
    mkpath(dirname(path))
    write(path, token)
    chmod(path, 0o600)
    return nothing
end

"""
    delete_token()

Remove token from the disk.
"""
delete_token() = rm(get_token_path(); force=true)
