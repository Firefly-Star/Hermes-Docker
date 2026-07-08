#!/usr/bin/env python3
"""Export Hermes provider metadata from an installed Hermes source tree.

Usage inside the Hermes container/source tree:
  python scripts/export-hermes-providers.py > data/hermes-providers.json

This project commits the generated JSON so first-time setup does not need an
already-running Hermes container.
"""

from __future__ import annotations

import json

from hermes_cli.auth import PROVIDER_REGISTRY
from hermes_cli.models import (
    CANONICAL_PROVIDERS,
    OPENROUTER_MODELS,
    PROVIDER_GROUPS,
    _PROVIDER_MODELS,
)

SPECIAL_PROVIDERS = {
    "openrouter": {
        "api_key_env_vars": ["OPENROUTER_API_KEY"],
        "base_url_env_var": "OPENROUTER_BASE_URL",
        "default_base_url": "https://openrouter.ai/api/v1",
        "auth_type": "api_key",
        "setup_supported": True,
        "models": OPENROUTER_MODELS,
    },
    "custom": {
        "api_key_env_vars": ["CUSTOM_LLM_API_KEY"],
        "base_url_env_var": "CUSTOM_LLM_BASE_URL",
        "default_base_url": "",
        "auth_type": "api_key",
        "setup_supported": True,
        "models": [],
    },
}


def main() -> None:
    providers = []
    seen = set()
    for entry in CANONICAL_PROVIDERS:
        seen.add(entry.slug)
        registry = PROVIDER_REGISTRY.get(entry.slug)
        api_key_env_vars = list(getattr(registry, "api_key_env_vars", ()) or []) if registry else []
        auth_type = str(getattr(registry, "auth_type", "") or "") if registry else ""
        item = {
            "slug": entry.slug,
            "label": entry.label,
            "description": entry.tui_desc,
            "api_key_env_vars": api_key_env_vars,
            "base_url_env_var": str(getattr(registry, "base_url_env_var", "") or "") if registry else "",
            "default_base_url": str(getattr(registry, "inference_base_url", "") or "") if registry else "",
            "auth_type": auth_type,
            "setup_supported": bool(api_key_env_vars) or entry.slug == "custom",
            "models": list(_PROVIDER_MODELS.get(entry.slug, [])),
        }
        if entry.slug in SPECIAL_PROVIDERS:
            item.update(SPECIAL_PROVIDERS[entry.slug])
            item["models"] = list(item.get("models") or [])
        providers.append(item)

    if "custom" not in seen:
        providers.append(
            {
                "slug": "custom",
                "label": "Custom endpoint",
                "description": "Custom OpenAI-compatible endpoint (enter URL manually)",
                **SPECIAL_PROVIDERS["custom"],
            }
        )

    print(
        json.dumps(
            {
                "source": "Hermes CANONICAL_PROVIDERS / PROVIDER_REGISTRY / _PROVIDER_MODELS",
                "providers": providers,
                "groups": PROVIDER_GROUPS,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
