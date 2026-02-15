import os;
import from dotenv { load_dotenv }
import from byllm.lib { Model }

with entry {
    # Load environment variables once at server startup.
    load_dotenv();
}

# Centralized LLM env contract for the whole app.
# `LLM_MODEL`: provider/model id used by byLLM/litellm.
# `LLM_API_KEY`: optional explicit key override.
# `LLM_BASE_URL`: optional proxy/custom endpoint.
glob llm_model = os.getenv("LLM_MODEL", "claude-sonnet-4-20250514"),
     llm_api_key = os.getenv("LLM_API_KEY", ""),
     llm_base_url = os.getenv("LLM_BASE_URL", "");

# Shared LLM instance used across modules.
# Note: Provider-specific env vars (e.g. ANTHROPIC_API_KEY, GEMINI_API_KEY)
# are still supported by LiteLLM/byLLM.
glob llm = Model(
    model_name=llm_model,
    api_key=llm_api_key,
    config={"base_url": llm_base_url}
);
