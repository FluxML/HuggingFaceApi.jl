using HuggingFaceApi, Pkg
using OhMyArtifacts
using Dates
using Test, Pkg

using HuggingFaceApi: CONFIG_NAME, get_etag, with_endpoint

# https://github.com/huggingface/huggingface_hub/blob/f124f8be1e02ca9fbcda7a849e70271299ad5738/tests/testing_utils.py
const DUMMY_MODEL_ID = "julien-c/dummy-unknown"
const DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT = "f2c752cfc5c0ab6f4bdec59acea69eefbee381c2"
const DUMMY_MODEL_ID_REVISION_INVALID = "aaaaaaa"
const DUMMY_MODEL_ID_PINNED_SHA1 = "d9e9f15bc825e4b2c9249e9578f884bbcb5e3684"
const DUMMY_MODEL_ID_PINNED_SHA256 =
    "4b243c475af8d0a7754e87d7d096c92e5199ec2fe168a2ee7998e3b8e9bcb1d3"
const SAMPLE_DATASET_IDENTIFIER = "lhoestq/custom_squad"
const DATASET_ID = SAMPLE_DATASET_IDENTIFIER
const DUMMY_DATASET_ID = "lhoestq/test"
const DUMMY_DATASET_ID_REVISION_ONE_SPECIFIC_COMMIT =
    "81d06f998585f8ee10e6e3a2ea47203dc75f2a16"

const DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT = "e25d55a1c4933f987c46cc75d8ffadd67f257c61"
# One particular commit for DATASET_ID
const DATASET_SAMPLE_PY_FILE = "custom_squad.py"

# https://github.com/huggingface/huggingface_hub/blob/0c78398d42af1bb605b8d69c277b1751067d0d57/tests/testing_constants.py
const USER = "__DUMMY_TRANSFORMERS_USER__"
const FULL_NAME = "Dummy User"
const PASS = "__DUMMY_TRANSFORMERS_PASS__"

# Not critical, only usable on the sandboxed CI instance.
const TOKEN = "hf_94wBhPGp6KrrTH3KDchhKpRxZwd6dmHWLL"

const ENDPOINT_STAGING = "https://hub-ci.huggingface.co"


@testset "HuggingFaceApi.jl" begin
    @test HuggingFaceURL(split("a/b/c",'/')...) == HuggingFaceURL("a", "b", "c")
    @test get_etag(HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME)) == DUMMY_MODEL_ID_PINNED_SHA1

    url_pinned_sha1 = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME;
                                     revision=DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test get_etag(url_pinned_sha1) != DUMMY_MODEL_ID_PINNED_SHA1

    url_pinned_sha256 = HuggingFaceURL(DUMMY_MODEL_ID, HuggingFaceApi.PYTORCH_WEIGHTS_NAME)
    @test get_etag(url_pinned_sha256) == DUMMY_MODEL_ID_PINNED_SHA256

    @test_throws ErrorException("request status HTTP/2 404: EntryNotFound") cached_download(HuggingFaceURL(DUMMY_MODEL_ID, "missing.bin"))

    url_invalid_revi = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME;
                                      revision = DUMMY_MODEL_ID_REVISION_INVALID)
    @test_throws ErrorException("request status HTTP/2 404: RevisionNotFound") cached_download(url_invalid_revi)

    url_invalid_repo = HuggingFaceURL("bert-base", "pytorch_model.bin")
    @test_throws ErrorException("request status HTTP/2 401: RepoNotFound") cached_download(url_invalid_repo)

    url1 = HuggingFaceURL(DATASET_ID, DATASET_SAMPLE_PY_FILE;
                          repo_type="datasets", revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    url2 = HuggingFaceURL("datasets/$DATASET_ID", DATASET_SAMPLE_PY_FILE;
                          revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    @test string(url1) == string(url2)
    @test get_etag(url1) != DUMMY_MODEL_ID_PINNED_SHA1

    dataset_lfs = HuggingFaceURL(DATASET_ID, "dev-v1.1.json";
                                 repo_type="datasets", revision=DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT)
    @test get_etag(dataset_lfs) == "95aa6a52d5d6a735563366753ca50492a658031da74f301ac5238b03966972c9"

    OhMyArtifacts.find_orphanages(; collect_delay=Hour(0))
    for url in [HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME), url_pinned_sha1, url_pinned_sha256, url1, url2]
        @test_nowarn cached_download(url)
        @test_nowarn HuggingFaceApi.remove_cache(url)
    end
    @test_logs (:info, r"4 MyArtifacts deleted") OhMyArtifacts.find_orphanages(; collect_delay=Hour(0))
end

@testset "Api endpoint" begin
    info = with_endpoint(ENDPOINT_STAGING) do
        HuggingFaceApi.whoami(TOKEN)
    end
    @test info.name == USER
    @test info.fullname == FULL_NAME
    @test info.orgs isa AbstractVector
    valid_org_i = findfirst(org->org.name == "valid_org", info.orgs)
    @test info.orgs[valid_org_i].apiToken isa AbstractString

    _api = HuggingFaceApi
    model_tags = _api.get_model_tags()
    for kind in ("library", "language", "license", "dataset", "pipeline_tag")
        @test !isempty(get(model_tags, kind))
    end

    dataset_tags = _api.get_dataset_tags()
    for kind in ("languages", "multilinguality", "language_creators", "task_categories",
                 "size_categories", "benchmark", "task_ids", "licenses")
        @test !isempty(get(dataset_tags, kind))
    end

    @test length(_api.list_models()) > 100
    m_google = _api.list_models(; author = "google", full=true)
    @test length(m_google) > 10
    @test all(m_google) do m
        "google" == m.author
    end
    m_bert = _api.list_models(; search = "bert")
    @test length(m_bert) > 10
    @test all(m_bert) do m
        occursin("bert", lowercase(m.modelId))
    end
    m_complex = _api.list_models(; filter=("bert", "jax"), sort="lastModified", direction=-1, limit=10)
    @test 10 >= length(m_complex) > 1
    @test all(m_complex) do m
        issubset(("bert", "jax"), m.tags)
    end
    m_cfg = _api.list_models(; filter="adapter-transformers", config=true, limit=20)
    @test (count(m_cfg) do m
             haskey(m, :config)
           end) > 0

    @test _api.model_info(DUMMY_MODEL_ID).sha != DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT
    mi = _api.model_info(DUMMY_MODEL_ID, revision=DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test mi.sha == DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT
    @test mi.securityStatus == Dict(:containsInfected=>false)
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

    @test length(_api.list_datasets()) > 100
    d = _api.list_datasets(; author="huggingface", search = "DataMeasurementsFiles")
    @test length(d) == 1
    @test "huggingface" == d[1].author
    @test occursin("DataMeasurementsFiles", d[1].id)
    d_raft =  _api.list_datasets(; filter = "benchmark:raft")
    @test length(d_raft) > 0
    @test "benchmark:raft" in d_raft[1].tags
    d_lang_creat = _api.list_datasets(; filter = "language_creators:crowdsourced")
    @test length(d_lang_creat) > 0
    @test "language_creators:crowdsourced" in d_lang_creat[1].tags
    d_lang_en = _api.list_datasets(; filter = "languages:en", limit=3)
    @test length(d_lang_en) > 0
    @test "languages:en" in d_lang_en[1].tags
    d_lang_en_fr = _api.list_datasets(; filter = ["languages:en", "languages:fr"])
    @test length(d_lang_en_fr) > 0
    @test "languages:en" in d_lang_en_fr[1].tags
    @test "languages:fr" in d_lang_en_fr[1].tags
    d_multiling = _api.list_datasets(; filter = "multilinguality:unknown")
    @test length(d_multiling) > 0
    @test "multilinguality:unknown" in d_multiling[1].tags
    d_sized = _api.list_datasets(; filter = "size_categories:100K<n<1M")
    @test length(d_sized) > 0
    @test "size_categories:100K<n<1M" in d_sized[1].tags
    d_task = _api.list_datasets(; filter = "task_categories:audio-classification")
    @test length(d_task) > 0
    @test "task_categories:audio-classification" in d_task[1].tags
    d_task_id = _api.list_datasets(; filter = "task_ids:automatic-speech-recognition")
    @test length(d_task_id) > 0
    @test "task_ids:automatic-speech-recognition" in d_task_id[1].tags
    d_full = _api.list_datasets(; full = true)
    @test length(d_full) > 100
    @test any(d->haskey(d, :cardData), d_full)
    d_author = _api.list_datasets(; author = "huggingface")
    @test length(d_author) > 1
    d_search = _api.list_datasets(; search = "wikipedia")
    @test length(d_search) > 10
    d_card = _api.list_datasets(; cardData = true)
    @test count(d->haskey(d, :cardData), d_card) > 0
    d_all = _api.list_datasets()
    @test all(d->!haskey(d, :cardData), d_all) > 0

    d_info = _api.dataset_info(DUMMY_DATASET_ID)
    @test d_info.cardData isa AbstractDict && length(d_info.cardData) > 0
    @test d_info.siblings isa AbstractVector && length(d_info.siblings) > 0
    @test d_info.sha != DUMMY_DATASET_ID_REVISION_ONE_SPECIFIC_COMMIT
    @test _api.dataset_info(DUMMY_DATASET_ID, revision=DUMMY_DATASET_ID_REVISION_ONE_SPECIFIC_COMMIT).sha ==
        DUMMY_DATASET_ID_REVISION_ONE_SPECIFIC_COMMIT

    mtr_all = _api.list_metrics()
    @test length(mtr_all) > 10
    @test any(m->haskey(m, :description), mtr_all)

    m_author = _api.list_models(; author = "muellerzr")
    @test length(m_author) > 0
    @test occursin("muellerzr", m_author[1].modelId)
    m_fb_bart = _api.list_models(; search = "facebook/bart-base")
    @test occursin("facebook/bart-base", m_fb_bart[1].modelId)
    m_fail = _api.list_models(; search = "muellerzr/testme")
    @test length(m_fail) == 0
    m_ms_tf = _api.list_models(; search = "microsoft/wavlm-base-sd", filter = "tensorflow")
    @test length(m_ms_tf) == 0
    m_ms_pt = _api.list_models(; search = "microsoft/wavlm-base-sd", filter = "pytorch")
    @test length(m_ms_pt) > 0
    m_task = _api.list_models(; search = "albert-base-v2", filter = "fill-mask")
    @test "fill-mask" == m_task[1].pipeline_tag
    @test occursin("albert-base-v2" , m_task[1].modelId)
    @test length(_api.list_models(; filter = "dummytask")) == 0
    @test length(_api.list_models(; filter = "en")) != length(_api.list_models(; filter = "fr"))
    m_cplx = _api.list_models(; filter = ("text-classification", "pytorch", "tensorflow"))
    @test length(m_cplx) > 1
    @test all(m->"text-classification" == m.pipeline_tag || "text-classification" in m.tags, m_cplx)
    @test all(m->"pytorch" in m.tags && "tensorflow" in m.tags, m_cplx)
    @test all(m->haskey(m, :cardData), _api.list_models(filter="co2_eq_emissions", cardData = true))
    @test all(m->!haskey(m, :cardData), _api.list_models(filter="co2_eq_emissions"))

    s_all = _api.list_spaces(; full = true)
    @test length(s_all) > 100
    @test any(s->haskey(s, :cardData), s_all)
    s_eval = _api.list_spaces(; author = "evaluate-metric")
    @test ["evaluate-metric/trec_eval", "evaluate-metric/perplexity"] ⊆ [s.id for s in s_eval]
    s_wiki = _api.list_spaces(; search = "wikipedia")
    @test occursin("wikipedia", lowercase(s_wiki[1].id))
    s_des = _api.list_spaces(; sort = "likes", direction = -1)
    s_asc = _api.list_spaces(; sort = "likes")
    @test s_des[1].likes > s_des[2].likes
    @test s_asc[end-1].likes < s_asc[end].likes
    @test length(_api.list_spaces(; limit=5)) == 5
    s_bert = _api.list_spaces(; models = "bert-base-uncased")
    @test "bert-base-uncased" in s_bert[1].models
    s_d_wiki = _api.list_spaces(; datasets = "wikipedia")
    @test "wikipedia" in s_d_wiki[1].datasets
    s_link = _api.list_spaces(; linked = true)
    @test any(s->haskey(s, :models), s_link)
    @test any(s->haskey(s, :datasets), s_link)
    @test any(s->haskey(s, :models) && haskey(s, :datasets), s_link)

    @test length(with_endpoint(_api.list_datasets, ENDPOINT_STAGING)) <
        length(with_endpoint(()->_api.list_datasets(TOKEN), ENDPOINT_STAGING))
    @test length(with_endpoint(_api.list_models, ENDPOINT_STAGING)) <
        length(with_endpoint(()->_api.list_models(TOKEN), ENDPOINT_STAGING))
    @test length(with_endpoint(_api.list_spaces, ENDPOINT_STAGING)) <=
        length(with_endpoint(()->_api.list_spaces(TOKEN), ENDPOINT_STAGING))
end
