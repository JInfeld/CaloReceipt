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

    def as_pantry_items(raw: any) -> list {
        if Array.isArray(raw) {
            return raw;
        }
        return [];
    }

    def as_nutrition_history(raw: any) -> list {
        if Array.isArray(raw) and raw.length > 0 {
            return raw;
        }
        return default_nutrition_history();
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

    def set_app_state(next_pantry: any = None, next_history: any = None, next_idx: any = None) -> None {
        pantry_items = as_pantry_items(app_state.pantry_items);
        nutrition_history = as_nutrition_history(app_state.nutrition_history);
        nutrition_selected_day_index = safe_day_index(
            app_state.nutrition_selected_day_index,
            nutrition_history.length
        );

        if next_pantry != None {
            pantry_items = as_pantry_items(next_pantry);
        }
        if next_history != None {
            nutrition_history = as_nutrition_history(next_history);
        }
        if next_idx != None {
            nutrition_selected_day_index = safe_day_index(next_idx, nutrition_history.length);
        }

        app_state = {
            "pantry_items": pantry_items,
            "nutrition_history": nutrition_history,
            "nutrition_selected_day_index": nutrition_selected_day_index
        };
    }

    def ensure_app_state_defaults() -> None {
        set_app_state(
            next_pantry=as_pantry_items(app_state.pantry_items),
            next_history=as_nutrition_history(app_state.nutrition_history),
            next_idx=safe_day_index(app_state.nutrition_selected_day_index, as_nutrition_history(app_state.nutrition_history).length)
        );
    }

    def reset_local_user_state() -> None {
        set_app_state(
            next_pantry=[],
            next_history=default_nutrition_history(),
            next_idx=0
        );
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

    async def load_user_state() -> None {
        ensure_app_state_defaults();
        try {
            pantry_result = root spawn GetPantryState();
            pantry_out = first_report_payload(pantry_result);
            if pantry_out and pantry_out.error {
                err_text = String(pantry_out.error);
                if is_auth_error_text(err_text) {
                    handle_auth_required("Session expired. Please sign in again.");
                    return;
                }
            } elif pantry_out and pantry_out.items != None {
                set_app_state(next_pantry=as_pantry_items(pantry_out.items));
            } else {
                set_app_state(next_pantry=[]);
            }

            nutrition_result = root spawn GetNutritionState();
            nutrition_out = first_report_payload(nutrition_result);
            if nutrition_out and nutrition_out.error {
                err_text = String(nutrition_out.error);
                if is_auth_error_text(err_text) {
                    handle_auth_required("Session expired. Please sign in again.");
                    return;
                }
            } elif nutrition_out and nutrition_out.weekly_history != None {
                next_weekly = as_nutrition_history(nutrition_out.weekly_history);
                idx = safe_day_index(nutrition_out.selected_day_index or 0, next_weekly.length);
                set_app_state(next_history=next_weekly, next_idx=idx);
            }

            profile_result = root spawn GetUserProfile();
            profile_out = first_report_payload(profile_result);
            if profile_out and profile_out.error {
                err_text = String(profile_out.error);
                if is_auth_error_text(err_text) {
                    handle_auth_required("Session expired. Please sign in again.");
                    return;
                }
                set_current_user_display_from_profile({});
            } else {
                set_current_user_display_from_profile(profile_out or {});
            }
        } except Exception as e {
            err_text = e.toString();
            if is_auth_error_text(err_text) {
                handle_auth_required("Session expired. Please sign in again.");
            }
        }
    }

    async def save_pantry_state(items: list) -> None {
        clean_items = as_pantry_items(items);
        set_app_state(next_pantry=clean_items);
        try {
            result = root spawn SavePantryState(items=clean_items);
            out = first_report_payload(result);
            if out and out.error and is_auth_error_text(String(out.error)) {
                handle_auth_required("Session expired. Please sign in again.");
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

        set_app_state(next_history=weekly, next_idx=idx);
        try {
            result = root spawn SaveNutritionState(
                selected_day_index=idx,
                weekly_history=weekly
            );
            out = first_report_payload(result);
            if out and out.error and is_auth_error_text(String(out.error)) {
                handle_auth_required("Session expired. Please sign in again.");
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
        try {
            await jacLogin(email, password);
            set_session_from_runtime();
            if is_logged_in {
                current_user_display = email;
                await load_user_state();
                auth_status = "Signed in.";
                auth_password = "";
            } else {
                auth_status = "Login did not create an active session.";
            }
        } except Exception as e {
            auth_status = "Login failed: " + e.toString();
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
        try {
            await jacSignup(email, password);
            await jacLogin(email, password);
            set_session_from_runtime();
            if is_logged_in {
                current_user_display = email;
                await load_user_state();
                auth_status = "Account created and signed in.";
                auth_password = "";
            } else {
                auth_status = "Account created, but auto-login was not confirmed.";
            }
        } except Exception as e {
            auth_status = "Signup failed: " + e.toString();
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
        reset_local_user_state();
        auth_password = "";
        auth_status = "You have been logged out.";
        auth_loading = false;
    }

    def handle_auth_required(message: str = "Session expired. Please sign in again.") -> None {
        jacLogout();
        is_logged_in = false;
        reset_local_user_state();
        auth_password = "";
        auth_status = message;
    }

    async can with entry {
        ensure_app_state_defaults();
        try {
            await jacLogout();
        } except Exception as _e {
            0;
        }
        is_logged_in = false;
        auth_status = "Please sign in to access your private data.";
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
                    <UserProfileTab on_auth_error={handle_auth_required} on_profile_change={handle_profile_change} />
                </div>
                <div style={{"display": ("block" if active_tab == "recipes" else "none")}}>
                    <RecipesTab
                        shared_state={app_state}
                        on_auth_error={handle_auth_required}
                        on_pantry_change={save_pantry_state}
                    />
                </div>
                <div style={{"display": ("block" if active_tab == "nutrition" else "none")}}>
                    <NutritionTab shared_state={app_state} on_nutrition_change={save_nutrition_state} />
                </div>
            </div>
        </div>;
}
