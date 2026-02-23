"""Unit tests for canonicalization and scoring utilities."""

from app.scoring.canonicalize import (
    canonicalize_args,
    canonicalize_number,
    canonicalize_string,
    canonicalize_tool_call,
    deep_equals,
    edit_distance,
    set_equals_unordered,
)


class TestCanonicalizeString:
    def test_basic_normalization(self):
        assert canonicalize_string("  Hello  World  ") == "hello world"

    def test_trailing_punctuation(self):
        assert canonicalize_string("answer is 42.") == "answer is 42"
        assert canonicalize_string("yes!") == "yes"

    def test_empty_string(self):
        assert canonicalize_string("") == ""

    def test_case_insensitive(self):
        assert canonicalize_string("PARIS") == canonicalize_string("paris")


class TestCanonicalizeNumber:
    def test_integer(self):
        assert canonicalize_number(42) == 42.0

    def test_float(self):
        assert canonicalize_number(3.14) == 3.14

    def test_string_number(self):
        assert canonicalize_number("42") == 42.0

    def test_comma_number(self):
        assert canonicalize_number("1,234,567") == 1234567.0

    def test_currency(self):
        assert canonicalize_number("$1,234.56") == 1234.56

    def test_non_number(self):
        assert canonicalize_number("hello") is None


class TestCanonicalizeArgs:
    def test_sorts_keys(self):
        result = canonicalize_args({"b": "2", "a": "1"})
        assert list(result.keys()) == ["a", "b"]

    def test_normalizes_strings(self):
        result = canonicalize_args({"key": "  Hello  "})
        assert result["key"] == "hello"

    def test_nested_dict(self):
        result = canonicalize_args({"outer": {"inner": "  VALUE  "}})
        assert result["outer"]["inner"] == "value"


class TestCanonicalizeToolCall:
    def test_basic(self):
        result = canonicalize_tool_call("Calculator", {"expression": "2 + 3"})
        assert result["tool_name"] == "calculator"
        assert result["arguments"]["expression"] == "2 + 3"


class TestDeepEquals:
    def test_identical_dicts(self):
        assert deep_equals({"a": 1}, {"a": 1})

    def test_numeric_tolerance(self):
        assert deep_equals({"a": 1.0000001}, {"a": 1.0}, numeric_tolerance=0.001)

    def test_different_values(self):
        assert not deep_equals({"a": 1}, {"a": 2})

    def test_nested(self):
        assert deep_equals({"a": {"b": [1, 2, 3]}}, {"a": {"b": [1, 2, 3]}})

    def test_string_normalization(self):
        assert deep_equals("  HELLO  ", "hello")


class TestEditDistance:
    def test_identical(self):
        assert edit_distance(["a", "b", "c"], ["a", "b", "c"]) == 0

    def test_one_insertion(self):
        assert edit_distance(["a", "b"], ["a", "b", "c"]) == 1

    def test_one_deletion(self):
        assert edit_distance(["a", "b", "c"], ["a", "c"]) == 1

    def test_one_substitution(self):
        assert edit_distance(["a", "b"], ["a", "c"]) == 1

    def test_empty(self):
        assert edit_distance([], ["a", "b"]) == 2

    def test_both_empty(self):
        assert edit_distance([], []) == 0


class TestSetEqualsUnordered:
    def test_same_elements(self):
        assert set_equals_unordered([1, 2, 3], [3, 1, 2])

    def test_different_elements(self):
        assert not set_equals_unordered([1, 2], [1, 3])

    def test_empty(self):
        assert set_equals_unordered([], [])
