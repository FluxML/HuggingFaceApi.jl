using HuggingFaceApi, Pkg
using OhMyArtifacts
using HTTP
using Dates
using Test, Pkg

using HuggingFaceApi: CONFIG_NAME, get_etag

pkgversion(m::Module) = VersionNumber(Pkg.TOML.parsefile(joinpath(dirname(string(first(methods(m.eval)).file)), "..", "Project.toml"))["version"])

const StatusError = if pkgversion(HTTP) < v"1"
    HTTP.ExceptionRequest.StatusError
else
    HTTP.Exceptions.StatusError
end

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
const DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT = "e25d55a1c4933f987c46cc75d8ffadd67f257c61"
# One particular commit for DATASET_ID
const DATASET_SAMPLE_PY_FILE = "custom_squad.py"

@testset "HuggingFaceApi.jl" begin
    @test HuggingFaceURL(split("a/b/c",'/')...) == HuggingFaceURL("a", "b", "c")
    @test get_etag(HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME)) == DUMMY_MODEL_ID_PINNED_SHA1

    url_pinned_sha1 = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME;
                                     revision=DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT)
    @test get_etag(url_pinned_sha1) != DUMMY_MODEL_ID_PINNED_SHA1

    url_pinned_sha256 = HuggingFaceURL(DUMMY_MODEL_ID, HuggingFaceApi.PYTORCH_WEIGHTS_NAME)
    @test get_etag(url_pinned_sha256) == DUMMY_MODEL_ID_PINNED_SHA256

    @test_throws StatusError cached_download(HuggingFaceURL(DUMMY_MODEL_ID, "missing.bin"))

    url_invalid_revi = HuggingFaceURL(DUMMY_MODEL_ID, CONFIG_NAME;
                                      revision = DUMMY_MODEL_ID_REVISION_INVALID)
    @test_throws StatusError cached_download(url_invalid_revi)

    url_invalid_repo = HuggingFaceURL("bert-base", "pytorch_model.bin")
    @test_throws StatusError cached_download(url_invalid_repo)

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
    m_google = _api.list_models(; author = "google")
    @test length(m_google) > 10
    @test all(m_google) do m
        "google" in m.author
    end
    m_bert = _api.list_models(; search = "bert")
    @test length(m_bert) > 10
    @test all(m_bert) do m
        "bert" in lowercase(m.modelId)
    end
    m_complex = _api.list_models(; filter=("bert", "jax"), sort="lastModified", direction=-1, limit=10)
    @test 10 > length(m_complex) > 1
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
    @test "huggingface" in d.author
    @test "DataMeasurementsFiles" in d.id
end