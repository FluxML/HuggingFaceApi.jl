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

Login from huggingface hub and remove all authentication cache.
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
