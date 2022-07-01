using LibGit2

struct LoginBuffer <: IO
    secret::Base.SecretBuffer
end

function Base.readavailable(data::LoginBuffer)
    size = data.secret.size
    data.secret.ptr = size + 1
    return @view data.secret.data[1:size]
end
Base.eof(data::LoginBuffer) = Base.eof(data.secret)

function withbuf(f::Function, data::LoginBuffer)
    try
        return f(data)
    finally
        Base.shred!(data.secret)
    end
end

function LoginBuffer(cred::LibGit2.UserPasswordCredential)
    input = Base.SecretBuffer()
    write(input, "{\"username\" : \"")
    write(input, cred.user)
    write(input, "\", \"password\" : \"")
    write(input, cred.pass)
    write(input, "\"}")
    seekstart(input)
    return LoginBuffer(input)
end

function login_prompt(user::AbstractString = Base.prompt("username"))
    return LibGit2.UserPasswordCredential(user, Base.getpass("password"))
end

function erase_cred(user::AbstractString)
    helper = LibGit2.GitCredentialHelper(`git credential-store`)
    userpass = LibGit2.UserPasswordCredential(user)
    cred = LibGit2.GitCredential(userpass, get_endpoint())
    LibGit2.reject(helper, cred)
    Base.shred!(cred)
    Base.shred!(userpass)
    return nothing
end

function write_cred(userpass::LibGit2.UserPasswordCredential)
    helper = LibGit2.GitCredentialHelper(`git credential-store`)
    cred = LibGit2.GitCredential(userpass, get_endpoint())
    LibGit2.approve(helper, cred)
    Base.shred!(cred)
    return nothing
end

function read_cred(user::AbstractString)
    helper = LibGit2.GitCredentialHelper(`git credential-store`)
    userpass = LibGit2.UserPasswordCredential(user)
    cred = LibGit2.GitCredential(userpass, get_endpoint())
    LibGit2.fill!(helper, cred)
    Base.shred!(userpass)
    return cred
end

function maybe_login_prompt(user::AbstractString = Base.prompt("username"))
    cred = read_cred(user)
    if isempty(cred.password)
        Base.shred!(cred)
        return login_prompt(user)
    else
        return LibGit2.UserPasswordCredential(cred.username, cred.password)
    end
end

auth_pair(auth_token) = "authorization"=>"Bearer $auth_token"
auth_header(auth_token) = [auth_pair(auth_token)]
auth_header!(headers, auth_token) = push!(headers, auth_pair(auth_token))
auth_pair(::Nothing) = nothing
auth_header(::Nothing) = Pair{String,String}[]
auth_header!(headers, ::Nothing) = headers

ensure_token(::Nothing) = error("No token provided and saved token not found")
ensure_token(token) = token

"""
    get_token()

Get the token stored on disk.
"""
function get_token()
    path = get_token_path()
    return isfile(path) ? read(path, String) : nothing
end

"""
    save_token(token)

Write token to the disk for future use.
"""
function save_token(token)
    path = get_token_path()
    mkpath(dirname(path))
    write(path, token)
    return nothing
end

"""
    delete_token()

Remove token from the disk.
"""
delete_token() = rm(get_token_path(); force=true)
