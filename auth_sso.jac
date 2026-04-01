import from sso_auth { get_provider_manifest }

def:pub get_sso_providers() -> dict {
    return get_provider_manifest();
}
