import pytest

def test_verify_valid_comparison_dir(comparison_dir):
    assert(len(comparison_dir) > 0)