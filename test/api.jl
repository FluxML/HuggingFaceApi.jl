const _api = HuggingFaceApi

@testset "auth" begin
    info = with_endpoint(ENDPOINT_STAGING) do
        _api.whoami(TOKEN)
    end
    @test info.name == USER
    @test info.fullname == FULL_NAME
    @test info.orgs isa AbstractVector
    valid_org = info.orgs[findfirst(org -> org.name == "valid_org", info.orgs)]
    @test valid_org.fullname == "Dummy Org"
    @test haskey(valid_org, "roleInOrg")
    @test info.auth.type == "access_token"

    with_endpoint(ENDPOINT_STAGING) do
        _api.login(TOKEN)
        @test _api.get_token() == TOKEN
        @test _api.whoami().name == USER
        _api.logout()
        @test isnothing(_api.get_token())
    end
    @test_throws ErrorException with_endpoint(() -> _api.login("hf_invalid"), ENDPOINT_STAGING)
    @test isnothing(_api.get_token())
end

@testset "tags" begin
    model_tags = _api.get_model_tags()
    for kind in ("library", "language", "license", "dataset", "pipeline_tag")
        @test !isempty(get(model_tags, kind, []))
    end
    dataset_tags = _api.get_dataset_tags()
    for kind in ("language", "license", "task_categories", "size_categories", "task_ids", "benchmark")
        @test !isempty(get(dataset_tags, kind, []))
    end
    @test any(t -> t.id == "language:en", dataset_tags["language"])
end

@testset "models" begin
    @test length(_api.list_models()) > 100
    m_google = _api.list_models(; author = "google", full=true)
    @test length(m_google) > 10
    @test all(m -> m.author == "google", m_google)
    m_bert = _api.list_models(; search = "bert")
    @test length(m_bert) > 10
    @test all(m -> occursin("bert", lowercase(m.modelId)), m_bert)
    m_complex = _api.list_models(; filter=("bert", "jax"), sort="lastModified", direction=-1, limit=10)
    @test 10 >= length(m_complex) > 1
    @test all(m -> issubset(("bert", "jax"), m.tags), m_complex)
    m_cfg = _api.list_models(; filter="adapter-transformers", config=true, limit=20)
    @test count(m -> haskey(m, "config"), m_cfg) > 0

    m_en = _api.list_models(; filter = "en", limit = 100)
    m_fr = _api.list_models(; filter = "fr", limit = 100)
    @test all(m -> "en" in m.tags, m_en)
    @test all(m -> "fr" in m.tags, m_fr)
    @test Set(m.id for m in m_en) != Set(m.id for m in m_fr)

    # pages hold at most 1000 results, `limit` follows the next ones
    @test length(_api.list_models(; filter = "text-classification")) <= 1000
    @test length(_api.list_models(; filter = "text-classification", limit = 1500)) == 1500

    @test _api.model_info(DUMMY_MODEL_ID).sha != DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT
    mi = _api.model_info(DUMMY_MODEL_ID, revision=DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test mi.sha == DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT
    @test mi.securityRepoStatus.scansDone isa Bool
    @test mi.securityRepoStatus.filesWithIssues isa AbstractVector
    @test _api.list_repo_files(DUMMY_MODEL_ID) == [
        ".gitattributes",
        "README.md",
        "config.json",
        "flax_model.msgpack",
        "merges.txt",
        "pytorch_model.bin",
        "tf_model.h5",
        "vocab.json",
    ]
    @test _api.list_model_files(DUMMY_MODEL_ID) == _api.list_repo_files(DUMMY_MODEL_ID)

    m_author = _api.list_models(; author = "muellerzr")
    @test length(m_author) > 0
    @test occursin("muellerzr", m_author[1].modelId)
    m_fb_bart = _api.list_models(; search = "facebook/bart-base")
    @test occursin("facebook/bart-base", m_fb_bart[1].modelId)
    @test isempty(_api.list_models(; search = "muellerzr/testme"))
    @test isempty(_api.list_models(; search = "microsoft/wavlm-base-sd", filter = "tensorflow"))
    @test !isempty(_api.list_models(; search = "microsoft/wavlm-base-sd", filter = "pytorch"))
    m_task = _api.list_models(; search = "albert-base-v2", filter = "fill-mask")
    @test "fill-mask" == m_task[1].pipeline_tag
    @test occursin("albert-base-v2" , m_task[1].modelId)
    @test isempty(_api.list_models(; filter = "dummytask"))
    m_cplx = _api.list_models(; filter = ("text-classification", "pytorch", "tensorflow"))
    @test length(m_cplx) > 1
    @test all(m -> "text-classification" == get(m, "pipeline_tag", nothing) || "text-classification" in m.tags, m_cplx)
    @test all(m -> "pytorch" in m.tags && "tensorflow" in m.tags, m_cplx)
    @test all(m -> haskey(m, "cardData"), _api.list_models(filter="co2_eq_emissions", cardData = true))
    @test all(m -> !haskey(m, "cardData"), _api.list_models(filter="co2_eq_emissions"))
end

@testset "datasets" begin
    @test length(_api.list_datasets()) > 100
    d = _api.list_datasets(; author="huggingface", search = "DataMeasurementsFiles")
    @test length(d) == 1
    @test "huggingface" == d[1].author
    @test occursin("DataMeasurementsFiles", d[1].id)
    for filter in ("benchmark:official", "language_creators:crowdsourced", "language:en", "license:mit",
                   "multilinguality:monolingual", "size_categories:100K<n<1M",
                   "task_categories:automatic-speech-recognition", "task_ids:extractive-qa")
        ds = _api.list_datasets(; filter, limit = 3)
        @test length(ds) > 0
        @test all(d -> filter in d.tags, ds)
    end
    d_en_fr = _api.list_datasets(; filter = ["language:en", "language:fr"], limit = 3)
    @test length(d_en_fr) > 0
    @test all(d -> issubset(["language:en", "language:fr"], d.tags), d_en_fr)
    d_full = _api.list_datasets(; full = true)
    @test length(d_full) > 100
    @test any(d -> haskey(d, "cardData"), d_full)
    @test length(_api.list_datasets(; author = "huggingface")) > 1
    @test length(_api.list_datasets(; search = "wikipedia")) > 10
    @test count(d -> haskey(d, "cardData"), _api.list_datasets(; cardData = true)) > 0
    @test all(d -> !haskey(d, "cardData"), _api.list_datasets())

    d_info = _api.dataset_info(DATASET_ID)
    @test d_info.cardData isa AbstractDict && length(d_info.cardData) > 0
    @test d_info.siblings isa AbstractVector && length(d_info.siblings) > 0
    @test d_info.sha != DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT
    @test _api.dataset_info(DATASET_ID, revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT).sha ==
        DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT
    @test DATASET_SAMPLE_PY_FILE in _api.list_dataset_files(DATASET_ID; revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)

    mtr_all = _api.list_metrics()
    @test length(mtr_all) > 10
    @test any(m -> haskey(m, "description"), mtr_all)
end

@testset "spaces" begin
    s_all = _api.list_spaces(; full = true)
    @test length(s_all) > 100
    @test any(s -> haskey(s, "cardData"), s_all)
    s_author = _api.list_spaces(; author = "julien-c")
    @test length(s_author) > 10
    @test all(s -> startswith(s.id, "julien-c/"), s_author)
    s_wiki = _api.list_spaces(; search = "wikipedia")
    @test occursin("wikipedia", lowercase(s_wiki[1].id))
    s_likes = _api.list_spaces(; sort = "likes", direction = -1, limit = 100)
    @test issorted([s.likes for s in s_likes]; rev = true)
    @test length(_api.list_spaces(; limit=5)) == 5
    s_bert = _api.list_spaces(; models = "bert-base-uncased")
    @test "bert-base-uncased" in s_bert[1].models
    s_d_wiki = _api.list_spaces(; datasets = "wikipedia")
    @test "wikipedia" in s_d_wiki[1].datasets
    s_link = _api.list_spaces(; linked = true)
    @test any(s -> haskey(s, "models"), s_link)
    @test any(s -> haskey(s, "datasets"), s_link)
    @test any(s -> haskey(s, "models") && haskey(s, "datasets"), s_link)
end

@testset "private repos" begin
    staging(f) = with_endpoint(f, ENDPOINT_STAGING)
    @test !any(m -> m.private, staging(() -> _api.list_models(nothing; author = USER)))
    @test any(m -> m.private, staging(() -> _api.list_models(TOKEN; author = USER)))
    @test !any(d -> d.private, staging(() -> _api.list_datasets(nothing; author = USER)))
    @test any(d -> d.private, staging(() -> _api.list_datasets(TOKEN; author = USER)))
end
