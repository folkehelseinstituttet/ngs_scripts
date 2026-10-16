from pathlib import Path

import pytest


@pytest.fixture(params=["fluseq_wrapper.sh", "fluseq_fasta_wrapper.sh"])
def wrapper(request):
    return Path(__file__).resolve().parents[1] / request.param
