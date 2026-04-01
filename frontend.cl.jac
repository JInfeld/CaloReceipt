import from tab_receipt_upload { ReceiptUploadTab }
import from tab_dashboard_ai { DashboardAiTab }
import from tab_user_profile { UserProfileTab }
import from tab_recipes { RecipesTab }
import from tab_nutrition { NutritionTab }
import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }
sv import from user { SavePantryState, GetPantryState, SaveNutritionState, GetNutritionState, GetUserProfile, SaveUserProfile }

def:pub app() -> JsxElement {
    has active_tab: str = "receipt";
    has app_state: dict = {
        "pantry_items": [],
        "nutrition_history": [],
        "nutrition_selected_day_index": 0
    };
    has is_logged_in: bool = false;
    has auth_email: str = "";
    has auth_password: str = "";
    has auth_mode: str = "login";
    has auth_loading: bool = false;
    has auth_status: str = "Please sign in to access your private data.";
    has active_user_key: str = "";
    has current_user_display: str = "";
    has is_hydrating_user_state: bool = false;
    has pantry_merge_timer_id: int = -1;
    has requires_profile_setup: bool = false;
    has signup_name: str = "";
    has signup_age: str = "";
    has signup_height: str = "";
    has signup_weight: str = "";
    has signup_goal_weight: str = "";
    has signup_sex: str = "MALE";
    has signup_fitness_level: str = "MODERATELY_ACTIVE";
    has signup_goal: str = "MAINTENANCE";
    has signup_dietary_notes: str = "";
    has signup_allergy_notes: str = "";
    has sso_providers: dict = {
        "google": {"configured": false, "login_path": "/sso/google/login", "register_path": "/sso/google/register"},
        "apple": {"configured": false, "login_path": "/sso/apple/login", "register_path": "/sso/apple/register"}
    };

    def tab_button_style(tab_id: str) -> dict {
        is_active = active_tab == tab_id;
        return {
            "padding": "10px 14px",
            "borderRadius": "999px",
            "border": ("1px solid #10243f" if is_active else "1px solid #9cb5cf"),
            "background": ("#10243f" if is_active else "#f7fbff"),
            "color": ("#f7fbff" if is_active else "#10243f"),
            "fontWeight": "700",
            "letterSpacing": "0.01em"
        };
    }

    def is_valid_tab(tab_id: str) -> bool {
        return (
            tab_id == "receipt" or
            tab_id == "dashboard" or
            tab_id == "profile" or
            tab_id == "recipes" or
            tab_id == "nutrition"
        );
    }

    def set_tab(tab_id: str) -> None {
        if is_valid_tab(tab_id) {
            active_tab = tab_id;
            return;
        }
        active_tab = "receipt";
    }

    def default_nutrition_history() -> list {
        return [
            {"day": "Mon", "protein": 82, "carbs": 71, "fat": 66, "move": 74},
            {"day": "Tue", "protein": 88, "carbs": 79, "fat": 70, "move": 81},
            {"day": "Wed", "protein": 92, "carbs": 76, "fat": 68, "move": 79},
            {"day": "Thu", "protein": 73, "carbs": 64, "fat": 58, "move": 62},
            {"day": "Fri", "protein": 96, "carbs": 88, "fat": 77, "move": 91},
            {"day": "Sat", "protein": 84, "carbs": 72, "fat": 71, "move": 86},
            {"day": "Sun", "protein": 90, "carbs": 75, "fat": 73, "move": 84}
        ];
    }

    def auth_error_text() -> str {
        return [("Working... " if auth_loading else "Ready. "), auth_status].join("");
    }

    def sso_status_storage_key() -> str {
        return "caloreceipt:sso_status";
    }

    def sso_display_name_storage_key() -> str {
        return "caloreceipt:sso_display_name";
    }

    def normalized_pathname(raw: any) -> str {
        path = String(raw or "").trim();
        if path.length == 0 {
            return "/";
        }
        if not path.startsWith("/") {
            path = "/" + path;
        }
        if path.length > 1 and path.endsWith("/") {
            path = path.slice(0, path.length - 1);
        }
        return path;
    }

    def current_pathname() -> str {
        try {
            return normalized_pathname(window.location.pathname or "/");
        } except Exception as _e {
            0;
        }
        return "/";
    }

    def is_auth_route() -> bool {
        return current_pathname() == "/auth";
    }

    def sync_route_with_auth_state(session_logged_in: bool, needs_profile: bool = false) -> None {
        target_path = ("/auth" if (not session_logged_in or needs_profile) else "/");
        if current_pathname() == target_path {
            return;
        }
        try {
            window.location.replace(target_path);
            return;
        } except Exception as _e {
            0;
        }
        window.location.assign(target_path);
    }

    def route_transition_shell(title: str, message: str) -> JsxElement {
        return
            <div
                style={{
                    "minHeight": "100vh",
                    "background": "radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%)",
                    "fontFamily": "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif",
                    "color": "#10243f",
                    "padding": "22px",
                    "display": "grid",
                    "placeItems": "center"
                }}
            >
                <div
                    style={{
                        "width": "min(520px, 100%)",
                        "background": "#ffffffde",
                        "border": "1px solid #d2e3f5",
                        "borderRadius": "18px",
                        "padding": "20px",
                        "display": "grid",
                        "gap": "14px"
                    }}
                >
                    <div>
                        <h1 style={{"margin": "0", "fontSize": "2rem", "letterSpacing": "0.02em"}}>{title}</h1>
                        <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                            {message}
                        </p>
                    </div>
                    <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                        {auth_error_text()}
                    </div>
                </div>
            </div>;
    }

    def is_listish(raw: any) -> bool {
        if not raw {
            return false;
        }
        if Array.isArray(raw) {
            return true;
        }
        try {
            raw_len = parseInt(String(raw.length));
            if isNaN(raw_len) or raw_len < 0 {
                return false;
            }
            probe = raw.map(lambda item: any -> any : item);
            if Array.isArray(probe) {
                return true;
            }
        } except Exception as _e {
            0;
        }
        return false;
    }

    def as_pantry_items(raw: any) -> list {
        if is_listish(raw) {
            return raw;
        }
        return [];
    }

    def norm_name(raw: any) -> str {
        return String(raw or "").trim().toLowerCase().split(" ").filter(
            lambda part: str -> bool { return part.trim().length > 0; }
        ).join(" ");
    }

    def norm_unit(raw: any) -> str {
        text = String(raw or "PIECE").trim().toUpperCase();
        if not text {
            return "PIECE";
        }
        return text;
    }

    def num_or_zero(raw: any) -> float {
        parsed = parseFloat(String(raw or "0"));
        if isNaN(parsed) {
            return 0.0;
        }
        return parsed;
    }

    def qty_or_one(raw: any) -> float {
        parsed = parseFloat(String(raw or "1").trim());
        if isNaN(parsed) or parsed <= 0 {
            return 1.0;
        }
        return parsed;
    }

    def per_serving_merge_value(left_value: any, left_qty: float, right_value: any, right_qty: float) -> float {
        total_qty = left_qty + right_qty;
        if total_qty <= 0.0 {
            return 0.0;
        }
        return (
            (num_or_zero(left_value) * left_qty) +
            (num_or_zero(right_value) * right_qty)
        ) / total_qty;
    }

    def total_quantity_value(raw_qty: any, fallback_qty: any = 0.0) -> float {
        qty_value = num_or_zero(raw_qty);
        if qty_value > 0.0 {
            return qty_value;
        }
        return num_or_zero(fallback_qty);
    }

    def merge_identical_pantry_items(items: list) -> list {
        merged: list = [];
        for item in items {
            item_name = String(item.name or "").trim();
            if not item_name {
                continue;
            }
            item_unit = norm_unit(item.unit);
            item_serving_size = String(item.serving_size or "").trim();
            item_package_unit = norm_unit(item.package_unit or item.unit);
            found = false;
            next_merged: list = [];
            for cur in merged {
                if norm_name(cur.name) == norm_name(item_name) and norm_unit(cur.unit) == item_unit and String(cur.serving_size or "").trim() == item_serving_size and norm_unit(cur.package_unit or cur.unit) == item_package_unit {
                    cur_qty = qty_or_one(cur.quantity);
                    item_qty = qty_or_one(item.quantity);
                    total_qty = cur_qty + item_qty;
                    cur_package_qty = total_quantity_value(cur.package_quantity, cur.quantity);
                    item_package_qty = total_quantity_value(item.package_quantity, item.quantity);
                    next_merged = next_merged.concat([{
                        "name": item_name,
                        "quantity": total_qty,
                        "unit": item_unit,
                        "cost": per_serving_merge_value(cur.cost, cur_qty, item.cost, item_qty),
                        "protein": per_serving_merge_value(cur.protein, cur_qty, item.protein, item_qty),
                        "carb": per_serving_merge_value(cur.carb, cur_qty, item.carb, item_qty),
                        "fat": per_serving_merge_value(cur.fat, cur_qty, item.fat, item_qty),
                        "serving_size": item_serving_size,
                        "package_quantity": cur_package_qty + item_package_qty,
                        "package_unit": item_package_unit
                    }]);
                    found = true;
                } else {
                    next_merged = next_merged.concat([cur]);
                }
            }
            if not found {
                next_merged = next_merged.concat([{
                    "name": item_name,
                    "quantity": qty_or_one(item.quantity),
                    "unit": item_unit,
                    "cost": num_or_zero(item.cost),
                    "protein": num_or_zero(item.protein),
                    "carb": num_or_zero(item.carb),
                    "fat": num_or_zero(item.fat),
                    "serving_size": item_serving_size,
                    "package_quantity": total_quantity_value(item.package_quantity, item.quantity),
                    "package_unit": item_package_unit
                }]);
            }
            merged = next_merged;
        }
        return merged;
    }

    def as_nutrition_history(raw: any) -> list {
        if is_listish(raw) and raw.length > 0 {
            return raw;
        }
        return default_nutrition_history();
    }

    def error_message(raw: any, fallback: str = "Unknown error.") -> str {
        if not raw {
            return fallback;
        }
        try {
            if raw.error and String(raw.error).trim().length > 0 {
                return String(raw.error).trim();
            }
            if raw.message and String(raw.message).trim().length > 0 {
                return String(raw.message).trim();
            }
        } except Exception as _e {
            0;
        }
        text = String(raw).trim();
        if text.length > 0 and text != "[object Object]" {
            return text;
        }
        return fallback;
    }

    def now_ms() -> int {
        now_obj = Reflect.construct(Date, []);
        return parseInt(now_obj.getTime().toString());
    }

    def pantry_save_state() -> dict {
        if not globalThis.__caloreceipt_pantry_save_state {
            globalThis.__caloreceipt_pantry_save_state = {
                "in_flight": false,
                "has_pending": false,
                "pending_items": [],
                "pending_version": 0,
                "pending_snapshot": "",
                "last_version": 0,
                "last_saved_snapshot": ""
            };
        }
        return globalThis.__caloreceipt_pantry_save_state;
    }

    def reset_pantry_save_state() -> None {
        state = pantry_save_state();
        state.in_flight = false;
        state.has_pending = false;
        state.pending_items = [];
        state.pending_version = 0;
        state.pending_snapshot = "";
        state.last_version = 0;
        state.last_saved_snapshot = "";
    }

    def safe_day_index(raw: any, history_len: int = 0) -> int {
        idx = parseInt(String(raw));
        if isNaN(idx) or idx < 0 {
            return 0;
        }
        if history_len > 0 and idx >= history_len {
            return 0;
        }
        return idx;
    }

    def split_csv(text: str) -> list {
        return String(text or "").split(",").map(
            lambda item: str -> str { return item.trim(); }
        ).filter(
            lambda item: str -> bool { return item.length > 0; }
        );
    }

    def parse_profile_num(raw: str, fallback: float = -1.0) -> float {
        parsed = parseFloat(String(raw or "").trim());
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def normalized_profile_choice(raw: any) -> str {
        return String(raw or "").trim().toUpperCase();
    }

    def profile_has_any_data(profile: dict = {}) -> bool {
        if not profile {
            return false;
        }
        return (
            String(profile.username or "").trim().length > 0 or
            String(profile.age or "").trim().length > 0 or
            String(profile.sex or "").trim().length > 0 or
            String(profile.height or "").trim().length > 0 or
            String(profile.weight or "").trim().length > 0 or
            String(profile.goal or "").trim().length > 0 or
            String(profile.fitness_level or "").trim().length > 0 or
            (is_listish(profile.dietary_restrictions) and profile.dietary_restrictions.length > 0) or
            (is_listish(profile.allergies) and profile.allergies.length > 0)
        );
    }

    def profile_has_key_info(profile: dict = {}) -> bool {
        if not profile_has_any_data(profile) {
            return false;
        }

        age_num = parseInt(String(profile.age or "").trim());
        height_num = parse_profile_num(String(profile.height or ""), -1.0);
        weight_num = parse_profile_num(String(profile.weight or ""), -1.0);
        sex_val = normalized_profile_choice(profile.sex);
        fitness_val = normalized_profile_choice(profile.fitness_level);
        goal_val = normalized_profile_choice(profile.goal);

        if isNaN(age_num) or age_num <= 0 or height_num <= 0 or weight_num <= 0 {
            return false;
        }
        if not (sex_val == "MALE" or sex_val == "FEMALE" or sex_val == "OTHER" or sex_val == "PREFER_NOT_TO_SAY") {
            return false;
        }
        if not (
            fitness_val == "SEDENTARY" or
            fitness_val == "LIGHTLY_ACTIVE" or
            fitness_val == "MODERATELY_ACTIVE" or
            fitness_val == "VERY_ACTIVE" or
            fitness_val == "ATHLETE"
        ) {
            return false;
        }
        if not (
            goal_val == "FAT_LOSS" or
            goal_val == "MAINTENANCE" or
            goal_val == "LEAN_BULK" or
            goal_val == "MUSCLE_GAIN" or
            goal_val == "ENDURANCE_PERFORMANCE"
        ) {
            return false;
        }
        return true;
    }

    def build_signup_profile_payload() -> dict {
        age_num = parseInt(String(signup_age or "").trim());
        height_num = parse_profile_num(signup_height, -1.0);
        weight_num = parse_profile_num(signup_weight, -1.0);
        goal_weight_num = parse_profile_num(signup_goal_weight, 0.0);

        if isNaN(age_num) or age_num <= 0 or height_num <= 0 or weight_num <= 0 {
            return {};
        }
        if goal_weight_num < 0 {
            goal_weight_num = 0.0;
        }

        return {
            "username": String(signup_name or "").trim(),
            "age": age_num,
            "sex": signup_sex,
            "height": height_num,
            "weight": weight_num,
            "goal_weight": goal_weight_num,
            "dietary_restrictions": split_csv(signup_dietary_notes),
            "allergies": split_csv(signup_allergy_notes),
            "fitness_level": signup_fitness_level,
            "goal": signup_goal
        };
    }

    def reset_signup_survey() -> None {
        signup_name = "";
        signup_age = "";
        signup_height = "";
        signup_weight = "";
        signup_goal_weight = "";
        signup_sex = "MALE";
        signup_fitness_level = "MODERATELY_ACTIVE";
        signup_goal = "MAINTENANCE";
        signup_dietary_notes = "";
        signup_allergy_notes = "";
    }

    def cache_key(suffix: str) -> str {
        user_key = active_user_key.trim().toLowerCase();
        if user_key.length == 0 {
            user_key = auth_email.trim().toLowerCase();
        }
        if user_key.length == 0 {
            user_key = "anonymous";
        }
        return ["caloreceipt", user_key, suffix].join(":");
    }

    def auth_user_key_storage_key() -> str {
        return "caloreceipt:auth_user_key";
    }

    def normalized_user_key(raw: any) -> str {
        return String(raw or "").trim().toLowerCase();
    }

    async def post_authenticated_walker(walker_name: str, payload: dict = {}) -> dict {
        jac_token = localStorage.getItem("jac_token") or "";
        response = await fetch(
            "/walker/".concat(walker_name),
            {
                "method": "POST",
                "headers": {
                    "Content-Type": "application/json",
                    "Authorization": ("Bearer " + jac_token) if jac_token else ""
                },
                "credentials": "include",
                "body": JSON.stringify(payload)
            }
        );
        raw_text = await response.text();
        response_payload = {};
        try {
            response_payload = JSON.parse(raw_text);
        } except Exception as _e {
            response_payload = {"error": raw_text};
        }
        if not response.ok {
            return {
                "ok": false,
                "status": response.status,
                "error": error_message(response_payload, raw_text)
            };
        }
        return {"ok": true, "status": response.status, "payload": response_payload};
    }

    async def call_authenticated_walker(walker_name: str, payload: dict = {}) -> dict {
        walker_result = await post_authenticated_walker(walker_name, payload);
        if walker_result.ok {
            return first_report_payload(walker_result.payload);
        }
        return {"error": walker_result.error, "status": walker_result.status};
    }

    def remember_active_user_key(raw: any) -> None {
        next_key = normalized_user_key(raw);
        active_user_key = next_key;
        if next_key.length > 0 {
            auth_email = next_key;
            try {
                localStorage.setItem(auth_user_key_storage_key(), next_key);
            } except Exception as _e {
                0;
            }
            return;
        }
        try {
            localStorage.removeItem(auth_user_key_storage_key());
        } except Exception as _e {
            0;
        }
    }

    def restore_active_user_key() -> None {
        try {
            stored_key = normalized_user_key(localStorage.getItem(auth_user_key_storage_key()));
            if stored_key.length > 0 {
                active_user_key = stored_key;
                if auth_email.trim().length == 0 {
                    auth_email = stored_key;
                }
            }
        } except Exception as _e {
            0;
        }
    }

    def consume_session_storage_text(storage_key: str) -> str {
        try {
            raw = String(sessionStorage.getItem(storage_key) or "").trim();
            if raw.length > 0 {
                sessionStorage.removeItem(storage_key);
                return raw;
            }
        } except Exception as _e {
            0;
        }
        return "";
    }

    def apply_pending_sso_context() -> None {
        pending_status = consume_session_storage_text(sso_status_storage_key());
        if pending_status.length > 0 {
            auth_status = pending_status;
        }
        pending_name = consume_session_storage_text(sso_display_name_storage_key());
        if pending_name.length > 0 and signup_name.trim().length == 0 {
            signup_name = pending_name;
        }
    }

    async def load_sso_providers() -> None {
        try {
            response = await fetch(
                "/function/get_sso_providers",
                {
                    "method": "POST",
                    "credentials": "include",
                    "headers": {"Content-Type": "application/json"},
                    "body": "{}"
                }
            );
            raw_text = await response.text();
            payload = {};
            try {
                payload = JSON.parse(raw_text);
            } except Exception as _e {
                payload = {};
            }
            if not response.ok {
                return;
            }
            providers_payload = {};
            try {
                providers_payload = payload.data.result.providers or {};
            } except Exception as _e {
                providers_payload = {};
            }
            if not providers_payload {
                return;
            }
            next_google = providers_payload.google or sso_providers.google;
            next_apple = providers_payload.apple or sso_providers.apple;
            sso_providers = {
                "google": {
                    "configured": Boolean(next_google.configured),
                    "login_path": String(next_google.login_path or "/sso/google/login"),
                    "register_path": String(next_google.register_path or "/sso/google/register")
                },
                "apple": {
                    "configured": Boolean(next_apple.configured),
                    "login_path": String(next_apple.login_path or "/sso/apple/login"),
                    "register_path": String(next_apple.register_path or "/sso/apple/register")
                }
            };
        } except Exception as _e {
            0;
        }
    }

    def sso_provider_configured(platform: str) -> bool {
        try {
            provider = sso_providers[platform];
            return Boolean(provider and provider.configured);
        } except Exception as _e {
            0;
        }
        return false;
    }

    def sso_provider_path(platform: str) -> str {
        operation = ("register" if auth_mode == "signup" else "login");
        try {
            provider = sso_providers[platform];
            next_path = String(provider[(operation + "_path")] or "").trim();
            if next_path.length > 0 {
                return next_path;
            }
        } except Exception as _e {
            0;
        }
        return ["/sso", platform, operation].join("/");
    }

    def sso_setup_message(platform: str) -> str {
        if platform == "google" {
            return "Google sign-in needs plugins.scale.sso.google.client_id and client_secret in jac.toml, or SSO_GOOGLE_CLIENT_ID and SSO_GOOGLE_CLIENT_SECRET env vars.";
        }
        if platform == "apple" {
            return "Apple sign-in needs plugins.scale.sso.apple.client_id plus either client_secret or team_id + key_id + private key in jac.toml, or the matching SSO_APPLE_* env vars.";
        }
        return "This sign-in provider is not configured on the server yet.";
    }

    def start_sso(platform: str) -> None {
        if auth_loading {
            return;
        }
        if not sso_provider_configured(platform) {
            auth_status = sso_setup_message(platform);
            return;
        }
        auth_status = ["Redirecting to ", platform.charAt(0).toUpperCase(), platform.slice(1), "..."].join("");
        window.location.assign(sso_provider_path(platform));
    }

    def load_cached_pantry() -> list {
        try {
            raw = localStorage.getItem(cache_key("pantry"));
            if raw and raw.length > 0 {
                parsed = JSON.parse(raw);
                return as_pantry_items(parsed);
            }
        } except Exception as _e {
            0;
        }
        return [];
    }

    def load_cached_nutrition() -> dict {
        try {
            raw = localStorage.getItem(cache_key("nutrition"));
            if raw and raw.length > 0 {
                parsed = JSON.parse(raw);
                history = as_nutrition_history(parsed.weekly_history);
                return {
                    "weekly_history": history,
                    "selected_day_index": safe_day_index(parsed.selected_day_index, history.length)
                };
            }
        } except Exception as _e {
            0;
        }
        return {
            "weekly_history": default_nutrition_history(),
            "selected_day_index": 0
        };
    }

    def load_cached_profile() -> dict {
        try {
            raw = localStorage.getItem(cache_key("profile"));
            if raw and raw.length > 0 {
                return JSON.parse(raw);
            }
        } except Exception as _e {
            0;
        }
        return {};
    }

    def save_cached_pantry(items: list) -> None {
        try {
            localStorage.setItem(cache_key("pantry"), JSON.stringify(items));
        } except Exception as _e {
            0;
        }
    }

    def save_cached_nutrition(weekly: list, idx: int) -> None {
        try {
            localStorage.setItem(
                cache_key("nutrition"),
                JSON.stringify({"weekly_history": weekly, "selected_day_index": idx})
            );
        } except Exception as _e {
            0;
        }
    }

    def save_cached_profile(profile: dict) -> None {
        try {
            localStorage.setItem(cache_key("profile"), JSON.stringify(profile));
        } except Exception as _e {
            0;
        }
    }

    def clear_cached_profile() -> None {
        try {
            localStorage.removeItem(cache_key("profile"));
        } except Exception as _e {
            0;
        }
    }

    def set_app_state(next_pantry: any, next_history: any, next_idx: any) -> None {
        pantry_items = as_pantry_items(next_pantry);
        nutrition_history = as_nutrition_history(next_history);
        nutrition_selected_day_index = safe_day_index(next_idx, nutrition_history.length);
        app_state = {
            "pantry_items": pantry_items,
            "nutrition_history": nutrition_history,
            "nutrition_selected_day_index": nutrition_selected_day_index
        };
    }

    def ensure_app_state_defaults() -> None {
        history = as_nutrition_history(app_state.nutrition_history);
        set_app_state(
            as_pantry_items(app_state.pantry_items),
            history,
            safe_day_index(app_state.nutrition_selected_day_index, history.length)
        );
    }

    def reset_local_user_state() -> None {
        set_app_state([], default_nutrition_history(), 0);
        current_user_display = "";
        requires_profile_setup = false;
        reset_pantry_save_state();
        reset_signup_survey();
    }

    def set_current_user_display_from_profile(profile: dict = {}) -> None {
        profile_name = String(profile.username or "").trim();
        if profile_name.length > 0 {
            current_user_display = profile_name;
            return;
        }
        email_text = active_user_key.trim();
        if email_text.length == 0 {
            email_text = auth_email.trim();
        }
        if email_text.length > 0 {
            current_user_display = email_text;
            return;
        }
        current_user_display = "Unknown User";
    }

    def handle_profile_change(profile: dict = {}) -> None {
        set_current_user_display_from_profile(profile);
        requires_profile_setup = not profile_has_key_info(profile);
    }

    def first_report_payload(raw_result: dict) -> dict {
        if not raw_result {
            return {};
        }
        if raw_result.reports and raw_result.reports.length > 0 {
            return raw_result.reports[0];
        }
        if raw_result.data and raw_result.data.reports and raw_result.data.reports.length > 0 {
            return raw_result.data.reports[0];
        }
        if raw_result.data and raw_result.data.result {
            return raw_result.data.result;
        }
        if raw_result.result {
            return raw_result.result;
        }
        return raw_result;
    }

    def is_auth_error_text(text: str) -> bool {
        lower = String(text or "").toLowerCase();
        return (
            lower.includes("401") or
            lower.includes("unauthorized") or
            lower.includes("forbidden") or
            lower.includes("token") or
            lower.includes("auth")
        );
    }

    def next_pantry_save_version() -> int {
        pantry_state = pantry_save_state();
        next_version = now_ms();
        if next_version <= pantry_state.last_version {
            next_version = pantry_state.last_version + 1;
        }
        pantry_state.last_version = next_version;
        return next_version;
    }

    async def load_user_state() -> dict {
        ensure_app_state_defaults();
        try {
            fallback_pantry = load_cached_pantry();
            fallback_nutrition = load_cached_nutrition();
            fallback_profile = load_cached_profile();
            next_pantry = [];
            next_weekly = fallback_nutrition.weekly_history;
            next_idx = fallback_nutrition.selected_day_index;
            has_profile = false;
            profile_payload = {};
            pantry_loaded = false;
            nutrition_loaded = false;

            pantry_out = await call_authenticated_walker("GetPantryState");
            if pantry_out and not pantry_out.error and pantry_out.items != None {
                clean_pantry = as_pantry_items(pantry_out.items);
                next_pantry = clean_pantry;
                save_cached_pantry(clean_pantry);
                pantry_loaded = true;
            }
            if not pantry_loaded {
                next_pantry = fallback_pantry;
            }

            nutrition_out = await call_authenticated_walker("GetNutritionState");
            if nutrition_out and not nutrition_out.error and nutrition_out.weekly_history != None {
                next_weekly = as_nutrition_history(nutrition_out.weekly_history);
                next_idx = safe_day_index(nutrition_out.selected_day_index or 0, next_weekly.length);
                save_cached_nutrition(next_weekly, next_idx);
                nutrition_loaded = true;
            }
            if not nutrition_loaded {
                next_weekly = fallback_nutrition.weekly_history;
                next_idx = fallback_nutrition.selected_day_index;
            }

            set_app_state(next_pantry, next_weekly, next_idx);

            profile_out = await call_authenticated_walker("GetUserProfile");
            if profile_out and profile_out.error {
                if profile_has_key_info(fallback_profile) {
                    has_profile = true;
                    profile_payload = fallback_profile;
                    save_cached_profile(fallback_profile);
                    set_current_user_display_from_profile(fallback_profile);
                } elif profile_has_any_data(fallback_profile) {
                    profile_payload = fallback_profile;
                    set_current_user_display_from_profile(fallback_profile);
                } else {
                    set_current_user_display_from_profile({});
                }
            } elif profile_has_key_info(profile_out) {
                has_profile = true;
                profile_payload = profile_out;
                save_cached_profile(profile_out);
                set_current_user_display_from_profile(profile_out);
            } elif profile_has_key_info(fallback_profile) {
                has_profile = true;
                profile_payload = fallback_profile;
                set_current_user_display_from_profile(fallback_profile);
            } elif profile_has_any_data(profile_out) {
                profile_payload = profile_out;
                save_cached_profile(profile_out);
                set_current_user_display_from_profile(profile_out);
            } elif profile_has_any_data(fallback_profile) {
                profile_payload = fallback_profile;
                set_current_user_display_from_profile(fallback_profile);
            } else {
                set_current_user_display_from_profile({});
            }
            return {"has_profile": has_profile, "profile": profile_payload};
        } except Exception as e {
            fallback_nutrition = load_cached_nutrition();
            fallback_profile = load_cached_profile();
            set_app_state(
                load_cached_pantry(),
                fallback_nutrition.weekly_history,
                fallback_nutrition.selected_day_index
            );
            if profile_has_key_info(fallback_profile) {
                set_current_user_display_from_profile(fallback_profile);
                return {"has_profile": true, "profile": fallback_profile};
            }
            if profile_has_any_data(fallback_profile) {
                set_current_user_display_from_profile(fallback_profile);
                return {"has_profile": false, "profile": fallback_profile};
            }
            set_current_user_display_from_profile({});
            return {"has_profile": false, "profile": {}};
        }
    }

    async def complete_profile_setup() -> None {
        profile_payload = build_signup_profile_payload();
        if Object.keys(profile_payload).length == 0 {
            auth_status = "Enter valid age, height, and current weight to continue.";
            return;
        }

        auth_loading = true;
        auth_status = "Saving your profile...";
        try {
            save_cached_profile(profile_payload);
            save_out = await call_authenticated_walker("SaveUserProfile", {"profile": profile_payload});
            if save_out and save_out.saved == false {
                auth_status = "Profile saved locally. Backend sync failed: " + error_message(save_out.error, "Unable to save profile.");
            } else {
                auth_status = "Profile saved. Welcome to CaloReceipt.";
            }
            set_current_user_display_from_profile(profile_payload);
            await load_user_state();
            requires_profile_setup = false;
            active_tab = "dashboard";
            reset_signup_survey();
            sync_route_with_auth_state(true, false);
        } except Exception as e {
            save_cached_profile(profile_payload);
            set_current_user_display_from_profile(profile_payload);
            requires_profile_setup = false;
            active_tab = "dashboard";
            auth_status = "Profile saved locally. Backend sync failed: " + error_message(e, "Unknown save error.");
            sync_route_with_auth_state(true, false);
        }
        auth_loading = false;
    }

    async def save_pantry_state(items: list) -> None {
        clean_items = merge_identical_pantry_items(as_pantry_items(items));
        snapshot = "";
        try {
            snapshot = JSON.stringify(clean_items);
        } except Exception as _e {
            snapshot = String(clean_items);
        }
        save_cached_pantry(clean_items);
        nutrition_cache = load_cached_nutrition();
        set_app_state(clean_items, nutrition_cache.weekly_history, nutrition_cache.selected_day_index);
        pantry_state = pantry_save_state();
        if snapshot == pantry_state.last_saved_snapshot and not pantry_state.in_flight and not pantry_state.has_pending {
            return;
        }
        if snapshot == pantry_state.pending_snapshot {
            return;
        }
        pantry_state.pending_items = clean_items;
        pantry_state.pending_version = next_pantry_save_version();
        pantry_state.pending_snapshot = snapshot;
        pantry_state.has_pending = true;

        if pantry_state.in_flight {
            return;
        }

        pantry_state.in_flight = true;
        try {
            while pantry_state.has_pending {
                items_to_save = pantry_state.pending_items;
                version_to_save = pantry_state.pending_version;
                snapshot_to_save = pantry_state.pending_snapshot;
                pantry_state.has_pending = false;

                try {
                    out = await call_authenticated_walker(
                        "SavePantryState",
                        {
                            "items": items_to_save,
                            "version": version_to_save
                        }
                    );
                    if out and out.error and is_auth_error_text(String(out.error)) {
                        handle_auth_required("Session expired. Please sign in again.");
                        return;
                    }
                    if out and out.saved == true {
                        pantry_state.last_saved_snapshot = snapshot_to_save;
                        if pantry_state.pending_snapshot == snapshot_to_save {
                            pantry_state.pending_snapshot = "";
                        }
                    }
                    if out and out.saved == false and out.stale != true {
                        return;
                    }
                } except Exception as e {
                    if is_auth_error_text(e.toString()) {
                        handle_auth_required("Session expired. Please sign in again.");
                        return;
                    }
                }
            }
        } finally {
            pantry_state.in_flight = false;
        }
    }

    async def save_nutrition_state(payload: dict) -> None {
        weekly = as_nutrition_history(payload.weekly_history);
        idx = safe_day_index(payload.selected_day_index or 0, weekly.length);

        save_cached_nutrition(weekly, idx);
        pantry_cache = load_cached_pantry();
        set_app_state(pantry_cache, weekly, idx);
        try {
            out = await call_authenticated_walker(
                "SaveNutritionState",
                {
                    "selected_day_index": idx,
                    "weekly_history": weekly
                }
            );
            if out and out.error and is_auth_error_text(String(out.error)) {
                handle_auth_required("Session expired. Please sign in again.");
                return;
            }
            if out and out.saved == false {
                return;
            }
        } except Exception as e {
            if is_auth_error_text(e.toString()) {
                handle_auth_required("Session expired. Please sign in again.");
            }
        }
    }

    async def do_login() -> None {
        email = auth_email.trim();
        password = auth_password;
        if not email or not password {
            auth_status = "Enter both email and password.";
            return;
        }

        auth_loading = true;
        auth_status = "Signing in...";
        is_hydrating_user_state = true;
        login_result = await jacLogin(email, password);
        login_success = (
            login_result == true or
            jacIsLoggedIn() or
            (login_result and login_result.success == true)
        );
        if login_success {
            remember_active_user_key(email);
            current_user_display = email;
            try {
                load_out = await load_user_state();
                needs_profile_setup = (not load_out.has_profile);
                requires_profile_setup = needs_profile_setup;
                is_logged_in = true;
                if needs_profile_setup {
                    auth_status = "Complete your profile before entering the dashboard.";
                } else {
                    auth_status = "Signed in.";
                }
                sync_route_with_auth_state(true, needs_profile_setup);
            } except Exception as e {
                is_logged_in = true;
                remember_active_user_key(email);
                current_user_display = email;
                requires_profile_setup = false;
                auth_status = "Signed in, but failed to load user data: " + error_message(e, "Unknown load error.");
                sync_route_with_auth_state(true, false);
            }
            is_hydrating_user_state = false;
            auth_password = "";
        } else {
            is_hydrating_user_state = false;
            is_logged_in = false;
            reset_local_user_state();
            auth_status = "Login failed: Invalid credentials.";
        }
        auth_loading = false;
    }

    async def do_signup() -> None {
        email = auth_email.trim();
        password = auth_password;
        if not email or not password {
            auth_status = "Enter both email and password.";
            return;
        }

        auth_loading = true;
        auth_status = "Creating account...";
        signup_result = await jacSignup(email, password);
        if not signup_result["success"] {
            auth_status = "Signup failed: " + error_message(signup_result["error"], "Unable to create account.");
            auth_loading = false;
            return;
        }

        # jacSignup logs the user in automatically on success
        is_logged_in = jacIsLoggedIn();
        is_hydrating_user_state = jacIsLoggedIn();
        remember_active_user_key(email);
        current_user_display = email;
        try {
            reset_signup_survey();
            requires_profile_setup = true;
            auth_status = "Account created. Complete your profile to continue.";
            sync_route_with_auth_state(true, true);
        } except Exception as e {
            auth_status = "Account created, but onboarding failed: " + error_message(e, "Unknown load error.");
        }
        is_hydrating_user_state = false;
        auth_password = "";
        auth_loading = false;
    }

    def do_logout() -> None {
        jacLogout();
        remember_active_user_key("");
        is_logged_in = false;
        is_hydrating_user_state = false;
        reset_local_user_state();
        auth_email = "";
        auth_password = "";
        auth_status = "You have been logged out.";
        sync_route_with_auth_state(false, false);
    }

    def handle_auth_required(message: str = "Session expired. Please sign in again.") -> None {
        if auth_email.trim().length == 0 and active_user_key.trim().length > 0 {
            auth_email = active_user_key;
        }
        remember_active_user_key("");
        is_logged_in = false;
        is_hydrating_user_state = false;
        reset_local_user_state();
        auth_password = "";
        auth_status = message;
        sync_route_with_auth_state(false, false);
    }

    def run_periodic_pantry_merge() -> None {
        current_items = as_pantry_items(app_state.pantry_items);
        merged_items = merge_identical_pantry_items(current_items);
        if JSON.stringify(merged_items) != JSON.stringify(current_items) {
            set_app_state(
                merged_items,
                as_nutrition_history(app_state.nutrition_history),
                safe_day_index(app_state.nutrition_selected_day_index, as_nutrition_history(app_state.nutrition_history).length)
            );
            save_cached_pantry(merged_items);
        }
    }

    async can with entry {
        ensure_app_state_defaults();
        restore_active_user_key();
        apply_pending_sso_context();
        await load_sso_providers();
        run_periodic_pantry_merge();
        if pantry_merge_timer_id >= 0 {
            window.clearInterval(pantry_merge_timer_id);
            pantry_merge_timer_id = -1;
        }
        pantry_merge_timer_id = window.setInterval(
            lambda -> None {
                run_periodic_pantry_merge();
            },
            4000
        );
        session_is_logged_in = jacIsLoggedIn();
        is_logged_in = session_is_logged_in;
        if session_is_logged_in {
            is_hydrating_user_state = true;
            auth_status = "Restoring your session...";
            try {
                load_out = await load_user_state();
                needs_profile_setup = (not load_out.has_profile);
                requires_profile_setup = needs_profile_setup;
                if needs_profile_setup {
                    auth_status = "Complete your profile before entering the dashboard.";
                } else {
                    auth_status = "Signed in.";
                }
                sync_route_with_auth_state(true, needs_profile_setup);
            } except Exception as e {
                requires_profile_setup = false;
                auth_status = "Signed in, but failed to restore user data: " + error_message(e, "Unknown load error.");
                sync_route_with_auth_state(true, false);
            }
            is_hydrating_user_state = false;
            return;
        }
        is_logged_in = false;
        is_hydrating_user_state = false;
        auth_status = "Please sign in to access your private data.";
        sync_route_with_auth_state(false, false);
    }

    can with exit {
        if pantry_merge_timer_id >= 0 {
            window.clearInterval(pantry_merge_timer_id);
            pantry_merge_timer_id = -1;
        }
    }

    if is_hydrating_user_state {
        return
            <div
                style={{
                    "minHeight": "100vh",
                    "background": "radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%)",
                    "fontFamily": "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif",
                    "color": "#10243f",
                    "padding": "22px",
                    "display": "grid",
                    "placeItems": "center"
                }}
            >
                <div
                    style={{
                        "width": "min(520px, 100%)",
                        "background": "#ffffffde",
                        "border": "1px solid #d2e3f5",
                        "borderRadius": "18px",
                        "padding": "20px",
                        "display": "grid",
                        "gap": "14px"
                    }}
                >
                    <div>
                        <h1 style={{"margin": "0", "fontSize": "2rem", "letterSpacing": "0.02em"}}>CaloReceipt</h1>
                        <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                            Restoring your workspace and account state.
                        </p>
                    </div>
                    <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                        {auth_error_text()}
                    </div>
                </div>
            </div>;
    }

    if not is_logged_in and not is_auth_route() {
        return route_transition_shell("Redirecting", "Sending you to the sign-in page.");
    }

    if is_logged_in and requires_profile_setup and not is_auth_route() {
        return route_transition_shell("Redirecting", "Sending you to profile setup.");
    }

    if is_logged_in and not requires_profile_setup and is_auth_route() {
        return route_transition_shell("Redirecting", "Returning you to the dashboard.");
    }

    if not is_logged_in {
        return
            <div
                style={{
                    "minHeight": "100vh",
                    "background": "radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%)",
                    "fontFamily": "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif",
                    "color": "#10243f",
                    "padding": "22px",
                    "display": "grid",
                    "placeItems": "center"
                }}
            >
                <div
                    style={{
                        "width": "min(520px, 100%)",
                        "background": "#ffffffde",
                        "border": "1px solid #d2e3f5",
                        "borderRadius": "18px",
                        "padding": "20px",
                        "display": "grid",
                        "gap": "14px"
                    }}
                >
                    <div>
                        <h1 style={{"margin": "0", "fontSize": "2rem", "letterSpacing": "0.02em"}}>CaloReceipt</h1>
                        <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                            {("Create your account first. We will ask for your profile right after signup." if auth_mode == "signup" else "Sign in to access your private profile, pantry, and recipe graph.")}
                        </p>
                    </div>
                    <div style={{"display": "flex", "gap": "8px"}}>
                        <button
                            onClick={lambda -> None { auth_mode = "login"; }}
                            style={{
                                "padding": "8px 12px",
                                "borderRadius": "999px",
                                "border": "1px solid #1d4ed8",
                                "background": ("#dbeafe" if auth_mode == "login" else "#ffffff"),
                                "fontWeight": "700"
                            }}
                        >
                            Login
                        </button>
                        <button
                            onClick={lambda -> None { auth_mode = "signup"; }}
                            style={{
                                "padding": "8px 12px",
                                "borderRadius": "999px",
                                "border": "1px solid #166534",
                                "background": ("#dcfce7" if auth_mode == "signup" else "#ffffff"),
                                "fontWeight": "700"
                            }}
                        >
                            Register
                        </button>
                    </div>
                    <div style={{"display": "grid", "gap": "10px"}}>
                        <div>
                            <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Email</label>
                            <input
                                value={auth_email}
                                onChange={lambda e: any -> None { auth_email = e.target.value; }}
                                placeholder="you@example.com"
                                style={{"width": "100%", "padding": "10px", "border": "1px solid #cbd5e1", "borderRadius": "10px"}}
                            />
                        </div>
                        <div>
                            <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Password</label>
                            <input
                                type="password"
                                value={auth_password}
                                onChange={lambda e: any -> None { auth_password = e.target.value; }}
                                placeholder="password"
                                style={{"width": "100%", "padding": "10px", "border": "1px solid #cbd5e1", "borderRadius": "10px"}}
                            />
                        </div>
                        <button
                            onClick={(do_login if auth_mode == "login" else do_signup)}
                            style={{
                                "padding": "10px 12px",
                                "borderRadius": "10px",
                                "border": ("1px solid #1d4ed8" if auth_mode == "login" else "1px solid #166534"),
                                "background": ("#dbeafe" if auth_mode == "login" else "#dcfce7"),
                                "fontWeight": "700"
                            }}
                        >
                            {("Sign In" if auth_mode == "login" else "Create Account")}
                        </button>
                        <div style={{"display": "grid", "gap": "8px"}}>
                            <button
                                onClick={lambda -> None { start_sso("google"); }}
                                style={{
                                    "padding": "10px 12px",
                                    "borderRadius": "10px",
                                    "border": ("1px solid #cbd5e1" if sso_provider_configured("google") else "1px solid #f59e0b"),
                                    "background": ("#ffffff" if sso_provider_configured("google") else "#fffbeb"),
                                    "fontWeight": "700"
                                }}
                            >
                                {("Continue with Google" if auth_mode == "login" else "Register with Google")}
                            </button>
                            <div style={{"fontSize": "0.9rem", "opacity": "0.78", "lineHeight": "1.4"}}>
                                {("Google sign-in is ready." if sso_provider_configured("google") else sso_setup_message("google"))}
                            </div>
                            <button
                                onClick={lambda -> None { start_sso("apple"); }}
                                style={{
                                    "padding": "10px 12px",
                                    "borderRadius": "10px",
                                    "border": ("1px solid #cbd5e1" if sso_provider_configured("apple") else "1px solid #f59e0b"),
                                    "background": ("#ffffff" if sso_provider_configured("apple") else "#fffbeb"),
                                    "fontWeight": "700"
                                }}
                            >
                                {("Continue with Apple" if auth_mode == "login" else "Register with Apple")}
                            </button>
                            <div style={{"fontSize": "0.9rem", "opacity": "0.78", "lineHeight": "1.4"}}>
                                {("Apple sign-in is ready." if sso_provider_configured("apple") else sso_setup_message("apple"))}
                            </div>
                        </div>
                    </div>
                    <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                        {auth_error_text()}
                    </div>
                </div>
            </div>;
    }

    if requires_profile_setup {
        return
            <div
                style={{
                    "minHeight": "100vh",
                    "background": "radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%)",
                    "fontFamily": "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif",
                    "color": "#10243f",
                    "padding": "22px"
                }}
            >
                <div
                    style={{
                        "maxWidth": "980px",
                        "margin": "0 auto",
                        "background": "#ffffffde",
                        "border": "1px solid #d2e3f5",
                        "borderRadius": "18px",
                        "padding": "22px",
                        "display": "grid",
                        "gap": "16px"
                    }}
                >
                    <div style={{"display": "flex", "justifyContent": "space-between", "gap": "12px", "alignItems": "center", "flexWrap": "wrap"}}>
                        <div>
                            <h1 style={{"margin": "0", "fontSize": "2rem", "letterSpacing": "0.02em"}}>Finish Your Profile</h1>
                            <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                                One quick survey before you enter the main dashboard. These answers personalize recipes, pantry planning, and nutrition targets.
                            </p>
                        </div>
                        <div style={{"padding": "8px 12px", "border": "1px solid #fbbf24", "background": "#fffbeb", "borderRadius": "999px", "fontWeight": "700"}}>
                            Step Required
                        </div>
                    </div>

                    <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                        {auth_error_text()}
                    </div>

                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(260px, 1fr))", "gap": "12px"}}>
                        <div style={{"border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>About You</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>Tell us the basics we need for your profile.</div>
                            </div>
                            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(150px, 1fr))", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Name</label>
                                    <input value={signup_name} onChange={lambda e: any -> None { signup_name = e.target.value; }} placeholder="Preferred name" style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Age</label>
                                    <input value={signup_age} onChange={lambda e: any -> None { signup_age = e.target.value; }} placeholder="Years" style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Sex</label>
                                    <select value={signup_sex} onChange={lambda e: any -> None { signup_sex = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}}>
                                        <option value="MALE">Male</option>
                                        <option value="FEMALE">Female</option>
                                        <option value="OTHER">Other</option>
                                        <option value="PREFER_NOT_TO_SAY">Prefer not to say</option>
                                    </select>
                                </div>
                            </div>
                        </div>

                        <div style={{"border": "1px solid #dcfce7", "background": "#f0fdf4", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>Body Metrics</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>We use these to tailor calories, macros, and portion suggestions.</div>
                            </div>
                            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(150px, 1fr))", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Height (in)</label>
                                    <input value={signup_height} onChange={lambda e: any -> None { signup_height = e.target.value; }} placeholder="70" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Current Weight (lb)</label>
                                    <input value={signup_weight} onChange={lambda e: any -> None { signup_weight = e.target.value; }} placeholder="170" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Goal Weight (lb)</label>
                                    <input value={signup_goal_weight} onChange={lambda e: any -> None { signup_goal_weight = e.target.value; }} placeholder="Optional" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                            </div>
                        </div>

                        <div style={{"border": "1px solid #fde68a", "background": "#fffbeb", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>Goals And Food Preferences</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>Set your activity level, overall goal, restrictions, and allergies.</div>
                            </div>
                            <div style={{"display": "grid", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Fitness Level</label>
                                    <select value={signup_fitness_level} onChange={lambda e: any -> None { signup_fitness_level = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}}>
                                        <option value="SEDENTARY">Sedentary</option>
                                        <option value="LIGHTLY_ACTIVE">Lightly active</option>
                                        <option value="MODERATELY_ACTIVE">Moderately active</option>
                                        <option value="VERY_ACTIVE">Very active</option>
                                        <option value="ATHLETE">Athlete</option>
                                    </select>
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Overall Goal</label>
                                    <select value={signup_goal} onChange={lambda e: any -> None { signup_goal = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}}>
                                        <option value="FAT_LOSS">Fat loss</option>
                                        <option value="MAINTENANCE">Maintenance</option>
                                        <option value="LEAN_BULK">Lean bulk</option>
                                        <option value="MUSCLE_GAIN">Muscle gain</option>
                                        <option value="ENDURANCE_PERFORMANCE">Endurance performance</option>
                                    </select>
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Dietary Restrictions</label>
                                    <input value={signup_dietary_notes} onChange={lambda e: any -> None { signup_dietary_notes = e.target.value; }} placeholder="Comma-separated, e.g. vegetarian, halal" style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Allergies</label>
                                    <input value={signup_allergy_notes} onChange={lambda e: any -> None { signup_allergy_notes = e.target.value; }} placeholder="Comma-separated, e.g. peanuts, shellfish" style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}} />
                                </div>
                            </div>
                        </div>
                    </div>

                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={complete_profile_setup} style={{"padding": "10px 14px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "700"}}>
                            Save And Enter Dashboard
                        </button>
                        <button onClick={do_logout} style={{"padding": "10px 14px", "borderRadius": "10px", "border": "1px solid #991b1b", "background": "#fee2e2", "fontWeight": "700"}}>
                            Log Out
                        </button>
                    </div>
                </div>
            </div>;
    }

    return
        <div
            style={{
                "minHeight": "100vh",
                "background": "radial-gradient(circle at 5% 10%, #ffe5b4 0%, #ffe5b400 30%), radial-gradient(circle at 95% 0%, #b7d7ff 0%, #b7d7ff00 35%), linear-gradient(135deg, #f4f8ff 0%, #f6fffb 50%, #fff7ef 100%)",
                "fontFamily": "'Space Grotesk', 'Avenir Next', 'Segoe UI', sans-serif",
                "color": "#10243f",
                "padding": "22px"
            }}
        >
            <div
                style={{
                    "maxWidth": "1180px",
                    "margin": "0 auto",
                    "display": "grid",
                    "gap": "16px"
                }}
            >
                <div
                    style={{
                        "background": "#ffffffd9",
                        "border": "1px solid #d2e3f5",
                        "borderRadius": "18px",
                        "padding": "18px",
                        "display": "grid",
                        "gap": "14px"
                    }}
                >
                    <div style={{"display": "flex", "justifyContent": "space-between", "gap": "10px", "flexWrap": "wrap", "alignItems": "center"}}>
                        <div>
                            <h1 style={{"margin": "0", "fontSize": "2rem", "letterSpacing": "0.02em"}}>CaloReceipt</h1>
                            <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                                Five-tab workspace for intake, planning, profile, recipes, and nutrition history.
                            </p>
                        </div>
                        <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                            <div
                                style={{
                                    "padding": "8px 12px",
                                    "border": "1px solid #86efac",
                                    "borderRadius": "999px",
                                    "fontWeight": "700",
                                    "background": "#f0fdf4"
                                }}
                            >
                                User: {current_user_display}
                            </div>
                            <div
                                style={{
                                    "padding": "8px 12px",
                                    "border": "1px solid #bfdbfe",
                                    "borderRadius": "999px",
                                    "fontWeight": "700",
                                    "background": "#eff6ff"
                                }}
                            >
                                Active Tab: {active_tab}
                            </div>
                            <button
                                onClick={do_logout}
                                style={{
                                    "padding": "8px 12px",
                                    "borderRadius": "999px",
                                    "border": "1px solid #991b1b",
                                    "background": "#fee2e2",
                                    "fontWeight": "700"
                                }}
                            >
                                Log Out
                            </button>
                        </div>
                    </div>
                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={lambda -> None { set_tab("receipt"); }} style={tab_button_style("receipt")}>
                            Receipt Upload
                        </button>
                        <button onClick={lambda -> None { set_tab("dashboard"); }} style={tab_button_style("dashboard")}>
                            Dashboard / AI Bot
                        </button>
                        <button onClick={lambda -> None { set_tab("profile"); }} style={tab_button_style("profile")}>
                            User Profile
                        </button>
                        <button onClick={lambda -> None { set_tab("recipes"); }} style={tab_button_style("recipes")}>
                            Recipes
                        </button>
                        <button onClick={lambda -> None { set_tab("nutrition"); }} style={tab_button_style("nutrition")}>
                            Nutrition
                        </button>
                    </div>
                </div>

                <div style={{"display": ("block" if active_tab == "receipt" else "none")}}>
                    <ReceiptUploadTab
                        shared_state={app_state}
                        on_auth_error={handle_auth_required}
                        on_pantry_change={save_pantry_state}
                        is_active={active_tab == "receipt"}
                    />
                </div>
                <div style={{"display": ("block" if active_tab == "dashboard" else "none")}}>
                    <DashboardAiTab on_auth_error={handle_auth_required} />
                </div>
                <div style={{"display": ("block" if active_tab == "profile" else "none")}}>
                    <UserProfileTab
                        on_auth_error={handle_auth_required}
                        on_profile_change={handle_profile_change}
                        user_storage_key={active_user_key}
                    />
                </div>
                <div style={{"display": ("block" if active_tab == "recipes" else "none")}}>
                    <RecipesTab
                        shared_state={app_state}
                        on_auth_error={handle_auth_required}
                        on_pantry_change={save_pantry_state}
                    />
                </div>
                <div style={{"display": ("block" if active_tab == "nutrition" else "none")}}>
                    <NutritionTab
                        shared_state={app_state}
                        on_nutrition_change={save_nutrition_state}
                        is_hydrating={is_hydrating_user_state}
                    />
                </div>
            </div>
        </div>;
}
