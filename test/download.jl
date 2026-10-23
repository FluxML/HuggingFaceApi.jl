using HuggingFaceApi: get_file_metadata, list_cache, remove_cache, try_to_load_from_cache, hf_hub_cache

errmsg(f) = try f(); "" catch e sprint(showerror, e) end

@testset "metadata" begin
    @test get_etag(HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME)) == DUMMY_MODEL_ID_PINNED_SHA1

    url_pinned_sha1 = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME;
                                     revision=DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test get_etag(url_pinned_sha1) != DUMMY_MODEL_ID_PINNED_SHA1
    @test get_file_metadata(url_pinned_sha1).commit_hash == DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT

    metadata = get_file_metadata(HuggingFaceURL(DUMMY_MODEL_ID, PYTORCH_WEIGHTS_NAME))
    @test metadata.etag == DUMMY_MODEL_ID_PINNED_SHA256
    @test metadata.size > 0

    @test occursin("EntryNotFound", errmsg(() -> cached_download(HuggingFaceURL(DUMMY_MODEL_ID, "missing.bin"))))
    @test occursin("RevisionNotFound", errmsg(() -> cached_download(
        HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME; revision = DUMMY_MODEL_ID_REVISION_INVALID))))
    @test occursin("RepoNotFound", errmsg(() -> cached_download(HuggingFaceURL("bert-base", "pytorch_model.bin"))))

    url1 = HuggingFaceURL(DATASET_ID, DATASET_SAMPLE_PY_FILE;
                          repo_type="datasets", revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    url2 = HuggingFaceURL("datasets/$DATASET_ID", DATASET_SAMPLE_PY_FILE;
                          revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    @test string(url1) == string(url2)
    @test get_etag(url1) != DUMMY_MODEL_ID_PINNED_SHA1

    dataset_lfs = HuggingFaceURL(DATASET_ID, "dev-v1.1.json";
                                 repo_type="datasets", revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    @test get_etag(dataset_lfs) == "95aa6a52d5d6a735563366753ca50492a658031da74f301ac5238b03966972c9"
end

@testset "cache" begin
    cache_dir = hf_hub_cache()
    storage = joinpath(cache_dir, "models--julien-c--dummy-unknown")

    config_url = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME)
    weight_url = HuggingFaceURL(DUMMY_MODEL_ID, PYTORCH_WEIGHTS_NAME)
    @test isnothing(try_to_load_from_cache(config_url))
    @test occursin("local_files_only", errmsg(() -> cached_download(config_url; local_files_only = true)))

    config = @test_nowarn cached_download(config_url)
    commit_hash = read(joinpath(storage, "refs", "main"), String)
    @test config == joinpath(storage, "snapshots", commit_hash, CONFIG_NAME)
    @test isfile(joinpath(storage, "blobs", DUMMY_MODEL_ID_PINNED_SHA1))
    @test startswith(read(joinpath(cache_dir, "CACHEDIR.TAG"), String), "Signature: 8a477f597d28d172789f06886806bc55\n")
    Sys.iswindows() || @test readlink(config) == joinpath("..", "..", "blobs", DUMMY_MODEL_ID_PINNED_SHA1)
    @test occursin("\"vocab_size\"", read(config, String))

    weight = hf_hub_download(DUMMY_MODEL_ID, PYTORCH_WEIGHTS_NAME)
    @test filesize(weight) == get_file_metadata(weight_url).size
    @test isfile(joinpath(storage, "blobs", DUMMY_MODEL_ID_PINNED_SHA256))

    @test cached_download(config_url) == config
    @test cached_download(config_url; local_files_only = true) == config
    @test try_to_load_from_cache(config_url) == config
    withenv("HF_HUB_OFFLINE" => "1") do
        @test hf_hub_download(DUMMY_MODEL_ID, CONFIG_NAME) == config
    end

    pinned_url = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME; revision = DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    pinned = cached_download(pinned_url)
    @test pinned == joinpath(storage, "snapshots", DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT, CONFIG_NAME)
    @test !isfile(joinpath(storage, "refs", DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT))
    @test cached_download(pinned_url; local_files_only = true) == pinned

    dataset_url = HuggingFaceURL(DATASET_ID, DATASET_SAMPLE_PY_FILE;
                                 repo_type = "dataset", revision = DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    @test isfile(cached_download(dataset_url))

    tmp = hf_hub_download(DUMMY_MODEL_ID, CONFIG_NAME; cache = false)
    @test !startswith(tmp, cache_dir)
    @test read(tmp, String) == read(config, String)
    rm(tmp)

    cache = list_cache()
    @test cache["model"][DUMMY_MODEL_ID]["main"] == sort([CONFIG_NAME, PYTORCH_WEIGHTS_NAME])
    @test cache["model"][DUMMY_MODEL_ID][DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT] == [CONFIG_NAME]
    @test cache["dataset"][DATASET_ID][DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT] == [DATASET_SAMPLE_PY_FILE]

    remove_cache(config_url)
    @test !ispath(config)
    @test !isfile(joinpath(storage, "blobs", DUMMY_MODEL_ID_PINNED_SHA1))
    @test isfile(weight)
    @test list_cache()["model"][DUMMY_MODEL_ID]["main"] == [PYTORCH_WEIGHTS_NAME]

    remove_cache(DUMMY_MODEL_ID; revision = "main")
    @test !ispath(weight)
    @test !isfile(joinpath(storage, "refs", "main"))
    @test isfile(pinned)
    @test !haskey(list_cache()["model"][DUMMY_MODEL_ID], "main")

    remove_cache(DUMMY_MODEL_ID)
    @test !ispath(storage)
    @test !haskey(list_cache(), "model")

    remove_cache(DATASET_ID; repo_type = "dataset")
    @test isempty(list_cache())
end
