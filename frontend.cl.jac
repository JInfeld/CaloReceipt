import from tab_receipt_upload { ReceiptUploadTab }
import from tab_dashboard_ai { DashboardAiTab }
import from tab_user_profile { UserProfileTab }
import from tab_recipes { RecipesTab }
import from tab_nutrition { NutritionTab }
import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }
sv import from user { SavePantryState, GetPantryState, SaveNutritionState, GetNutritionState, GetUserProfile }

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
    has current_user_display: str = "";
    has is_hydrating_user_state: bool = false;
    has pantry_merge_timer_id: int = -1;

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

    def is_listish(raw: any) -> bool {
        if raw == None {
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

    def merge_identical_pantry_items(items: list) -> list {
        merged: list = [];
        for item in items {
            item_name = String(item.name or "").trim();
            if not item_name {
                continue;
            }
            item_unit = norm_unit(item.unit);
            found = false;
            next_merged: list = [];
            for cur in merged {
                if norm_name(cur.name) == norm_name(item_name) and norm_unit(cur.unit) == item_unit {
                    next_merged = next_merged.concat([{
                        "name": item_name,
                        "quantity": qty_or_one(cur.quantity) + qty_or_one(item.quantity),
                        "unit": item_unit,
                        "cost": num_or_zero(cur.cost) + num_or_zero(item.cost),
                        "protein": num_or_zero(cur.protein) + num_or_zero(item.protein),
                        "carb": num_or_zero(cur.carb) + num_or_zero(item.carb),
                        "fat": num_or_zero(cur.fat) + num_or_zero(item.fat)
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
                    "fat": num_or_zero(item.fat)
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
        if raw == None {
            return fallback;
        }
        if raw == false {
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

    def cache_key(suffix: str) -> str {
        user_key = auth_email.trim().toLowerCase();
        if user_key.length == 0 {
            user_key = "anonymous";
        }
        return ["caloreceipt", user_key, suffix].join(":");
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
    }

    def set_current_user_display_from_profile(profile: dict = {}) -> None {
        profile_name = String(profile.username or "").trim();
        if profile_name.length > 0 {
            current_user_display = profile_name;
            return;
        }
        email_text = auth_email.trim();
        if email_text.length > 0 {
            current_user_display = email_text;
            return;
        }
        current_user_display = "Unknown User";
    }

    def handle_profile_change(profile: dict = {}) -> None {
        set_current_user_display_from_profile(profile);
    }

    def first_report_payload(raw_result: dict) -> dict {
        if raw_result == None {
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

    def set_session_from_runtime() -> None {
        is_logged_in = jacIsLoggedIn();
    }

    def token_from_auth_payload(payload: dict = {}) -> str {
        token = "";
        if payload and payload.data and payload.data.token {
            token = String(payload.data.token);
        } elif payload and payload.data and payload.data.result and payload.data.result.token {
            token = String(payload.data.result.token);
        } elif payload and payload.token {
            token = String(payload.token);
        } elif payload and payload.access_token {
            token = String(payload.access_token);
        }
        return token.trim();
    }

    async def auth_request(path: str, email: str, password: str) -> dict {
        try {
            response = await fetch(
                path,
                {
                    "method": "POST",
                    "headers": {"Content-Type": "application/json"},
                    "body": JSON.stringify({"username": email, "password": password})
                }
            );
            raw_text = await response.text();
            payload = {};
            try {
                payload = JSON.parse(raw_text);
            } except Exception as _parse_err {
                payload = {};
            }

            token = token_from_auth_payload(payload);
            if token.length > 0 {
                localStorage.setItem("jac_token", token);
            }

            err = "";
            if not response.ok {
                err = error_message(payload, "");
                if err.length == 0 {
                    if raw_text and raw_text.trim().length > 0 {
                        err = raw_text.trim();
                    } else {
                        err = ["HTTP ", String(response.status)].join("");
                    }
                }
            }

            return {
                "ok": response.ok,
                "status": response.status,
                "token": token,
                "error": err
            };
        } except Exception as e {
            return {
                "ok": false,
                "status": 0,
                "token": "",
                "error": error_message(e, "Auth request failed.")
            };
        }
    }

    async def attempt_login(email: str, password: str) -> dict {
        runtime_err = "";
        try {
            login_result = await jacLogin(email, password);
            if login_result == true or jacIsLoggedIn() {
                return {"ok": true, "error": ""};
            }
            runtime_err = error_message(login_result, "No auth token returned.");
        } except Exception as e {
            runtime_err = error_message(e, "Runtime login failed.");
        }

        api_out = await auth_request("/user/login", email, password);
        if api_out.ok and (api_out.token.length > 0 or jacIsLoggedIn()) {
            return {"ok": true, "error": ""};
        }
        if jacIsLoggedIn() {
            return {"ok": true, "error": ""};
        }

        parts: list = [];
        if runtime_err.trim().length > 0 {
            parts = parts.concat([runtime_err]);
        }
        api_err = error_message(api_out.error, "");
        if api_err.trim().length > 0 {
            parts = parts.concat([api_err]);
        }
        if parts.length == 0 {
            parts = ["Invalid username or password."];
        }
        return {"ok": false, "error": parts.join(" | ")};
    }

    async def attempt_signup(email: str, password: str) -> dict {
        runtime_err = "";
        try {
            signup_result = await jacSignup(email, password);
            if signup_result == true {
                return {"ok": true, "error": ""};
            }
            if signup_result and (signup_result.success == true or signup_result.ok == true) {
                return {"ok": true, "error": ""};
            }
            runtime_err = error_message(signup_result, "Signup was rejected.");
        } except Exception as e {
            runtime_err = error_message(e, "Runtime signup failed.");
        }

        api_out = await auth_request("/user/register", email, password);
        if api_out.ok {
            return {"ok": true, "error": ""};
        }

        parts: list = [];
        if runtime_err.trim().length > 0 {
            parts = parts.concat([runtime_err]);
        }
        api_err = error_message(api_out.error, "");
        if api_err.trim().length > 0 {
            parts = parts.concat([api_err]);
        }
        if parts.length == 0 {
            parts = ["Unable to create account."];
        }
        return {"ok": false, "error": parts.join(" | ")};
    }

    async def load_user_state() -> None {
        ensure_app_state_defaults();
        try {
            fallback_pantry = load_cached_pantry();
            fallback_nutrition = load_cached_nutrition();
            next_pantry = fallback_pantry;
            next_weekly = fallback_nutrition.weekly_history;
            next_idx = fallback_nutrition.selected_day_index;

            pantry_result = root spawn GetPantryState();
            pantry_out = first_report_payload(pantry_result);
            if pantry_out and not pantry_out.error and pantry_out.items != None {
                clean_pantry = as_pantry_items(pantry_out.items);
                if clean_pantry.length == 0 and fallback_pantry.length > 0 {
                    clean_pantry = fallback_pantry;
                }
                next_pantry = clean_pantry;
                save_cached_pantry(clean_pantry);
            }

            nutrition_result = root spawn GetNutritionState();
            nutrition_out = first_report_payload(nutrition_result);
            if nutrition_out and not nutrition_out.error and nutrition_out.weekly_history != None {
                next_weekly = as_nutrition_history(nutrition_out.weekly_history);
                next_idx = safe_day_index(nutrition_out.selected_day_index or 0, next_weekly.length);
                save_cached_nutrition(next_weekly, next_idx);
            }

            set_app_state(next_pantry, next_weekly, next_idx);

            profile_result = root spawn GetUserProfile();
            profile_out = first_report_payload(profile_result);
            if profile_out and profile_out.error {
                set_current_user_display_from_profile({});
            } else {
                set_current_user_display_from_profile(profile_out or {});
            }
        } except Exception as e {
            fallback_nutrition = load_cached_nutrition();
            set_app_state(
                load_cached_pantry(),
                fallback_nutrition.weekly_history,
                fallback_nutrition.selected_day_index
            );
            set_current_user_display_from_profile({});
        }
    }

    async def save_pantry_state(items: list) -> None {
        clean_items = merge_identical_pantry_items(as_pantry_items(items));
        save_cached_pantry(clean_items);
        nutrition_cache = load_cached_nutrition();
        set_app_state(clean_items, nutrition_cache.weekly_history, nutrition_cache.selected_day_index);
        try {
            result = root spawn SavePantryState(items=clean_items);
            out = first_report_payload(result);
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

    async def save_nutrition_state(payload: dict) -> None {
        weekly = as_nutrition_history(payload.weekly_history);
        idx = safe_day_index(payload.selected_day_index or 0, weekly.length);

        save_cached_nutrition(weekly, idx);
        pantry_cache = load_cached_pantry();
        set_app_state(pantry_cache, weekly, idx);
        try {
            result = root spawn SaveNutritionState(
                selected_day_index=idx,
                weekly_history=weekly
            );
            out = first_report_payload(result);
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
        login_out = await attempt_login(email, password);
        session_ok = (login_out.ok == true) or jacIsLoggedIn();
        is_logged_in = session_ok;
        if session_ok {
            is_hydrating_user_state = true;
            current_user_display = email;
            try {
                await load_user_state();
                auth_status = "Signed in.";
            } except Exception as e {
                auth_status = "Signed in, but failed to load user data: " + error_message(e, "Unknown load error.");
            }
            is_hydrating_user_state = false;
            auth_password = "";
        } else {
            is_hydrating_user_state = false;
            reset_local_user_state();
            auth_status = "Login failed: " + error_message(login_out.error, "Invalid credentials.");
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
        signup_out = await attempt_signup(email, password);
        if not signup_out.ok {
            auth_status = "Signup failed: " + error_message(signup_out.error, "Unable to create account.");
            auth_loading = false;
            return;
        }

        login_out = await attempt_login(email, password);
        session_ok = (login_out.ok == true) or jacIsLoggedIn();
        is_logged_in = session_ok;
        if session_ok {
            is_hydrating_user_state = true;
            current_user_display = email;
            try {
                await load_user_state();
                auth_status = "Account created and signed in.";
            } except Exception as e {
                auth_status = "Account created and signed in, but failed to load user data: " + error_message(e, "Unknown load error.");
            }
            is_hydrating_user_state = false;
            auth_password = "";
        } else {
            is_hydrating_user_state = false;
            auth_status = "Account created, but login failed: " + error_message(login_out.error, "Please sign in manually.");
        }
        auth_loading = false;
    }

    async def do_logout() -> None {
        auth_loading = true;
        try {
            await jacLogout();
        } except Exception as _e {
            0;
        }
        is_logged_in = false;
        is_hydrating_user_state = false;
        reset_local_user_state();
        auth_password = "";
        auth_status = "You have been logged out.";
        auth_loading = false;
    }

    def handle_auth_required(message: str = "Session expired. Please sign in again.") -> None {
        jacLogout();
        is_logged_in = false;
        is_hydrating_user_state = false;
        reset_local_user_state();
        auth_password = "";
        auth_status = message;
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
        try {
            await jacLogout();
        } except Exception as _e {
            0;
        }
        is_logged_in = false;
        is_hydrating_user_state = false;
        auth_status = "Please sign in to access your private data.";
    }

    can with exit {
        if pantry_merge_timer_id >= 0 {
            window.clearInterval(pantry_merge_timer_id);
            pantry_merge_timer_id = -1;
        }
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
                            Sign in to access your private profile, pantry, and recipe graph.
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
                    </div>
                    <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                        {auth_error_text()}
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
                    />
                </div>
                <div style={{"display": ("block" if active_tab == "dashboard" else "none")}}>
                    <DashboardAiTab on_auth_error={handle_auth_required} />
                </div>
                <div style={{"display": ("block" if active_tab == "profile" else "none")}}>
                    <UserProfileTab
                        on_auth_error={handle_auth_required}
                        on_profile_change={handle_profile_change}
                        user_storage_key={auth_email}
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
