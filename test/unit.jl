using HuggingFaceApi: DATASET_REPO, SPACE_REPO, repo_from_string, repo_folder_name, escape_uri,
    build_query, next_page, normalize_etag, is_commit_hash, check_relative_path, offline_mode

@testset "HuggingFaceURL" begin
    @test HuggingFaceURL(split("a/b/c",'/')...) == HuggingFaceURL("a", "b", "c")
    @test string(HuggingFaceURL("lysandre/arxiv-nlp", "config.json")) ==
        "https://huggingface.co/lysandre/arxiv-nlp/resolve/main/config.json"
    @test string(HuggingFaceURL("a/b", "sub dir", "f+1.json"; revision = "refs/pr/1")) ==
        "https://huggingface.co/a/b/resolve/refs%2Fpr%2F1/sub%20dir/f%2B1.json"

    @test repo_from_string(nothing) === nothing
    @test repo_from_string("model") === nothing
    @test repo_from_string("dataset") === repo_from_string("datasets") === DATASET_REPO()
    @test repo_from_string("space") === repo_from_string("spaces") === SPACE_REPO()
    @test repo_from_string(SPACE_REPO()) === SPACE_REPO()
    @test_throws ErrorException repo_from_string("foo")

    d1 = HuggingFaceURL("user/data", "f.txt"; repo_type = "dataset")
    d2 = HuggingFaceURL("datasets/user/data", "f.txt")
    @test d1 == d2
    @test d2.repo_id == "user/data"
    @test d2.repo_type === DATASET_REPO()
    @test string(d1) == "https://huggingface.co/datasets/user/data/resolve/main/f.txt"
    @test HuggingFaceURL("spaces/user/app", "app.py").repo_type === SPACE_REPO()

    @test repo_folder_name(HuggingFaceURL("julien-c/dummy-unknown", "config.json")) == "models--julien-c--dummy-unknown"
    @test repo_folder_name(d1) == "datasets--user--data"
    @test repo_folder_name(SPACE_REPO(), "gpt2") == "spaces--gpt2"

    @test with_endpoint(() -> string(HuggingFaceURL("a", "b")), "http://localhost") ==
        "http://localhost/a/resolve/main/b"
end

@testset "utils" begin
    @test escape_uri("a-b_c.d~e") == "a-b_c.d~e"
    @test escape_uri("100K<n<1M") == "100K%3Cn%3C1M"
    @test escape_uri("é") == "%C3%A9"
    @test escape_uri("a/b"; safe = "/") == "a/b"
    @test build_query([:filter => "a,b", :limit => 5, :full => true]) == "?filter=a,b&limit=5&full=true"

    @test next_page((; headers = ["Link" => "<https://huggingface.co/api/models?cursor=abc>; rel=\"next\""])) ==
        "https://huggingface.co/api/models?cursor=abc"
    @test isnothing(next_page((; headers = Pair{String,String}[])))

    @test normalize_etag("\"abc\"") == "abc"
    @test normalize_etag("W/\"abc\"") == "abc"
    @test is_commit_hash(DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test !is_commit_hash("main")
    @test !is_commit_hash(DUMMY_MODEL_ID_REVISION_INVALID)

    @test check_relative_path("sub/file.bin", "filename") == "sub/file.bin"
    @test check_relative_path("refs/pr/1", "revision") == "refs/pr/1"
    for path in ("../x", "a/../../x", "a\\..\\x", "/etc/passwd", "a//b", "")
        @test_throws ErrorException check_relative_path(path, "filename")
    end
    @test_throws ErrorException cached_download(HuggingFaceURL("a/b", "../../x"))

    withenv("HF_HUB_OFFLINE" => nothing, "TRANSFORMERS_OFFLINE" => nothing) do
        @test !offline_mode()
    end
    withenv("HF_HUB_OFFLINE" => "1") do
        @test offline_mode()
    end
    withenv("HF_HUB_OFFLINE" => "0", "TRANSFORMERS_OFFLINE" => "1") do
        @test !offline_mode()
    end
    withenv("HF_HUB_OFFLINE" => nothing, "TRANSFORMERS_OFFLINE" => "yes") do
        @test offline_mode()
    end
end

@testset "paths" begin
    withenv("HF_HOME" => "/tmp/hfhome", "HF_HUB_CACHE" => nothing, "HUGGINGFACE_HUB_CACHE" => nothing,
            "HF_TOKEN_PATH" => nothing) do
        @test HuggingFaceApi.hf_home() == "/tmp/hfhome"
        @test HuggingFaceApi.hf_hub_cache() == joinpath("/tmp/hfhome", "hub")
        @test HuggingFaceApi.get_token_path() == abspath(joinpath("/tmp/hfhome", "token"))
    end
    withenv("HF_HOME" => nothing, "XDG_CACHE_HOME" => "/tmp/xdg", "HF_HUB_CACHE" => "", "HUGGINGFACE_HUB_CACHE" => nothing) do
        @test HuggingFaceApi.hf_hub_cache() == joinpath("/tmp/xdg", "huggingface", "hub")
    end
    withenv("HF_HUB_CACHE" => "/tmp/hubcache") do
        @test HuggingFaceApi.hf_hub_cache() == "/tmp/hubcache"
    end
end

@testset "token" begin
    @test isnothing(HuggingFaceApi.get_token())
    HuggingFaceApi.save_token("hf_file\n")
    @test HuggingFaceApi.get_token() == "hf_file"
    Sys.iswindows() || @test filemode(HuggingFaceApi.get_token_path()) & 0o777 == 0o600
    withenv("HF_TOKEN" => " hf_env ") do
        @test HuggingFaceApi.get_token() == "hf_env"
    end
    withenv("HF_TOKEN" => "", "HUGGING_FACE_HUB_TOKEN" => "hf_legacy") do
        @test HuggingFaceApi.get_token() == "hf_legacy"
    end
    HuggingFaceApi.logout()
    @test isnothing(HuggingFaceApi.get_token())
    @test_throws ErrorException HuggingFaceApi.whoami()
end
