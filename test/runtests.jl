# Keep the user's cache and token out of the tests.
for key in ("HF_TOKEN", "HUGGING_FACE_HUB_TOKEN", "HF_HUB_OFFLINE", "HF_ENDPOINT", "HUGGINGFACE_CO_STAGING")
    delete!(ENV, key)
end
ENV["HF_HUB_CACHE"] = mktempdir()
ENV["HF_TOKEN_PATH"] = joinpath(mktempdir(), "token")

using HuggingFaceApi
using HuggingFaceApi: CONFIG_NAME, PYTORCH_WEIGHTS_NAME, get_etag, with_endpoint
using Aqua
using Test

# https://github.com/huggingface/huggingface_hub/blob/f124f8be1e02ca9fbcda7a849e70271299ad5738/tests/testing_utils.py
const DUMMY_MODEL_ID = "julien-c/dummy-unknown"
const DUMMY_MODEL_ID_REVISION_ONE_SPECIFIC_COMMIT = "f2c752cfc5c0ab6f4bdec59acea69eefbee381c2"
const DUMMY_MODEL_ID_REVISION_INVALID = "aaaaaaa"
const DUMMY_MODEL_ID_PINNED_SHA1 = "d9e9f15bc825e4b2c9249e9578f884bbcb5e3684"
const DUMMY_MODEL_ID_PINNED_SHA256 =
    "4b243c475af8d0a7754e87d7d096c92e5199ec2fe168a2ee7998e3b8e9bcb1d3"
const SAMPLE_DATASET_IDENTIFIER = "lhoestq/custom_squad"
const DATASET_ID = SAMPLE_DATASET_IDENTIFIER
const DATASET_REVISION_ID_ONE_SPECIFIC_COMMIT = "e25d55a1c4933f987c46cc75d8ffadd67f257c61"
const DATASET_SAMPLE_PY_FILE = "custom_squad.py"

# https://github.com/huggingface/huggingface_hub/blob/0c78398d42af1bb605b8d69c277b1751067d0d57/tests/testing_constants.py
const USER = "__DUMMY_TRANSFORMERS_USER__"
const FULL_NAME = "Dummy User"

# Not critical, only usable on the sandboxed CI instance.
const TOKEN = "hf_94wBhPGp6KrrTH3KDchhKpRxZwd6dmHWLL"

const ENDPOINT_STAGING = "https://hub-ci.huggingface.co"

@testset "HuggingFaceApi.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(HuggingFaceApi)
    end
    @testset "Unit" begin
        include("unit.jl")
    end
    @testset "Download" begin
        include("download.jl")
    end
    @testset "Api endpoint" begin
        include("api.jl")
    end
end
