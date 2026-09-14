"""Text-analysis providers for focus sessions and end-of-day reflections.

Mirrors the same structure as the scheduling providers: a Gemini REST
implementation that is used when an API key is configured, and a
deterministic heuristic fallback so the feature works offline (and in tests
when no key is available).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Protocol

import httpx

from app.core.config import settings


@dataclass(frozen=True)
class AnalysisResult:
    """The outcome of analyzing a reflection or a focus session.

    ``insight`` is a human-readable summary paragraph. ``tags`` are short
    keywords (for example "overwhelm", "unblocked", "procrastination")
    that the iOS side can reuse for charts and labels.
    """

    insight: str
    tags: list[str]


class TextAnalysisError(Exception):
    """Raised when an analysis provider fails."""


class TextAnalysisProvider(Protocol):
    def analyze_text(self, text: str) -> AnalysisResult:
        """Return a short analysis for the given free-form text."""
        ...


def default_analysis_provider() -> TextAnalysisProvider:
    if settings.gemini_api_key:
        return GeminiTextAnalysisProvider()
    return HeuristicTextAnalysisProvider()


class GeminiTextAnalysisProvider:
    """Calls the Gemini generateContent REST API for free-form text."""

    BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "gemini-2.0-flash",
        timeout: float = 45.0,
    ) -> None:
        self.api_key = api_key or settings.gemini_api_key
        self.model = model
        self.timeout = timeout

    def analyze_text(self, text: str) -> AnalysisResult:
        if not self.api_key:
            raise TextAnalysisError("Gemini API key is not configured")

        prompt = (
            "You help a busy professional reflect on their day. Given the "
            "free-form reflection below, produce a JSON object with exactly "
            'two keys: "insight" (a 1-3 sentence encouraging, concrete '
            'observation) and "tags" (an array of 1-4 short lowercase '
            'keywords such as "productive", "overwhelm", "distracted", '
            '"planning win"). No other text.\n\nReflection:\n'
            f"{text}"
        )
        try:
            response = httpx.post(
                f"{self.BASE_URL}/models/{self.model}:generateContent",
                params={"key": self.api_key},
                json={
                    "contents": [
                        {"role": "user", "parts": [{"text": prompt}]}
                    ],
                    "generationConfig": {
                        "responseMimeType": "application/json",
                        "temperature": 0.4,
                    },
                },
                timeout=self.timeout,
            )
            response.raise_for_status()
            payload = response.json()
            raw = (
                payload.get("candidates", [{}])[0]
                .get("content", {})
                .get("parts", [{}])[0]
                .get("text", "")
            )
            if not raw:
                raise TextAnalysisError("Gemini returned an empty response")
            data = json.loads(raw)
            return AnalysisResult(
                insight=str(data.get("insight", "")).strip()
                or "No insight returned.",
                tags=[
                    str(tag).strip().lower()
                    for tag in data.get("tags", [])
                    if str(tag).strip()
                ],
            )
        except httpx.HTTPError as exc:
            raise TextAnalysisError(f"Gemini request failed: {exc}") from exc
        except (TypeError, ValueError, json.JSONDecodeError) as exc:
            raise TextAnalysisError(f"Could not parse Gemini response: {exc}") from exc


class HeuristicTextAnalysisProvider:
    """Deterministic fallback that works without any API key."""

    POSITIVE = {
        "done",
        "finished",
        "completed",
        "focused",
        "proud",
        "win",
        "great",
        "good",
        "progress",
        "unblocked",
        "flow",
    }
    NEGATIVE = {
        "overwhel",
        "chaos",
        "distracted",
        "procrastinat",
        "stuck",
        "stressed",
        "behind",
        "missed",
        "exhausted",
        "cancelled",
        "delayed",
    }

    def analyze_text(self, text: str) -> AnalysisResult:
        lowered = text.lower()
        hits_pos = sum(1 for word in self.POSITIVE if word in lowered)
        hits_neg = sum(1 for word in self.NEGATIVE if word in lowered)

        tags: list[str] = []
        if hits_pos > hits_neg:
            tags.append("productive")
            insight = (
                "A good day: you got meaningful work done and can carry this "
                "momentum into tomorrow."
            )
        elif hits_neg > hits_pos:
            tags.append("overwhelm")
            insight = (
                "A heavy day. Pick the single most important task tomorrow "
                "and lower your expectations elsewhere."
            )
        else:
            insight = (
                "A steady day. Restating what went well and what to improve "
                "makes tomorrow more intentional."
            )
        return AnalysisResult(insight=insight, tags=tags)
