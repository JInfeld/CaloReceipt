import "./styles.css";
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
        "nutrition_selected_day_index": 0,
        "nutrition_targets": {}
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

    def tab_label(tab_id: str) -> str {
        if tab_id == "receipt" {
            return "Receipt Upload";
        }
        if tab_id == "dashboard" {
            return "Dashboard";
        }
        if tab_id == "profile" {
            return "User Profile";
        }
        if tab_id == "recipes" {
            return "Recipes";
        }
        if tab_id == "nutrition" {
            return "Nutrition";
        }
        return "Workspace";
    }

    def tab_summary(tab_id: str) -> str {
        if tab_id == "receipt" {
            return "Capture new grocery purchases and turn them into pantry inventory.";
        }
        if tab_id == "dashboard" {
            return "Review macro targets, recent progress, and AI grocery guidance.";
        }
        if tab_id == "profile" {
            return "Keep your body metrics, dietary rules, and goals current.";
        }
        if tab_id == "recipes" {
            return "Generate meals from your pantry and rank the recipes you actually make.";
        }
        if tab_id == "nutrition" {
            return "Track weekly macro completion and day-by-day trends.";
        }
        return "Five-tab workspace for intake, planning, profile, recipes, and nutrition history.";
    }

    def nav_link_class(tab_id: str) -> str {
        return ("cr-nav-link active" if active_tab == tab_id else "cr-nav-link");
    }

    def auth_mode_button_class(mode: str) -> str {
        return ("active" if auth_mode == mode else "");
    }

    def display_identity() -> str {
        name = String(current_user_display or "").trim();
        if name.length > 0 {
            return name;
        }
        email_text = String(auth_email or "").trim();
        if email_text.length > 0 {
            return email_text;
        }
        return "CaloReceipt";
    }

    def user_initials() -> str {
        source = display_identity().replace("@", " ").replace(".", " ").replace("_", " ").replace("-", " ");
        words = source.split(" ").filter(
            lambda word: str -> bool { return word.trim().length > 0; }
        );
        if words.length == 0 {
            return "CR";
        }
        if words.length == 1 {
            word = String(words[0] or "").trim();
            if word.length >= 2 {
                return word.slice(0, 2).toUpperCase();
            }
            return word.toUpperCase();
        }
        return [String(words[0]).charAt(0), String(words[1]).charAt(0)].join("").toUpperCase();
    }

    def greeting_name() -> str {
        identity = display_identity();
        first_part = identity.split("@")[0].split(" ")[0].trim();
        if first_part.length > 0 {
            return first_part;
        }
        return "there";
    }

    def greeting_text() -> str {
        hour = Reflect.construct(Date, []).getHours();
        prefix = "Good evening";
        if hour < 12 {
            prefix = "Good morning";
        } elif hour < 17 {
            prefix = "Good afternoon";
        }
        return [prefix, ", ", greeting_name()].join("");
    }

    def pad2(raw: any) -> str {
        parsed = parseInt(String(raw or "0"));
        if isNaN(parsed) or parsed < 0 {
            parsed = 0;
        }
        return ["0", String(parsed)].join("").slice(-2);
    }

    def nutrition_day_name_from_index(day_idx: int) -> str {
        names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        if day_idx < 0 or day_idx >= names.length {
            return "Day";
        }
        return names[day_idx];
    }

    def nutrition_date_key(date_obj: any) -> str {
        return [
            String(date_obj.getFullYear()),
            "-",
            pad2(date_obj.getMonth() + 1),
            "-",
            pad2(date_obj.getDate())
        ].join("");
    }

    def nutrition_day_label(date_obj: any) -> str {
        return [
            nutrition_day_name_from_index(date_obj.getDay()),
            " ",
            String(date_obj.getMonth() + 1),
            "/",
            String(date_obj.getDate())
        ].join("");
    }

    def start_of_week_date(anchor_ms: any = None) -> any {
        anchor_raw = parseInt(String(anchor_ms or "0"));
        anchor_value = (
            anchor_raw
            if (not isNaN(anchor_raw) and anchor_raw > 0)
            else parseInt(String(Reflect.construct(Date, []).getTime()))
        );
        start = Reflect.construct(Date, [anchor_value]);
        start.setHours(0);
        start.setMinutes(0);
        start.setSeconds(0);
        start.setMilliseconds(0);
        offset = ((start.getDay() + 6) % 7);
        start.setDate(start.getDate() - offset);
        return start;
    }

    def empty_nutrition_day(date_obj: any) -> dict {
        return {
            "date_key": nutrition_date_key(date_obj),
            "day": nutrition_day_name_from_index(date_obj.getDay()),
            "label": nutrition_day_label(date_obj),
            "calories_consumed": 0.0,
            "protein_consumed": 0.0,
            "carbs_consumed": 0.0,
            "fat_consumed": 0.0,
            "entries": []
        };
    }

    def default_nutrition_history(anchor_ms: any = None) -> list {
        week_start = start_of_week_date(anchor_ms);
        history: list = [];
        for idx=0 to idx<7 by idx+=1 {
            day_date = Reflect.construct(Date, [week_start.getTime()]);
            day_date.setDate(week_start.getDate() + idx);
            history = history.concat([empty_nutrition_day(day_date)]);
        }
        return history;
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
            <div className="cr-auth-page">
                <div className="login-container">
                    <div className="login-card cr-transition-card">
                        <div className="login-header">
                            <div className="login-logo">
                                <div className="logo-icon">
                                    <svg viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                                    </svg>
                                </div>
                                <span>CaloReceipt</span>
                            </div>
                            <h1 className="login-title">{title}</h1>
                            <p className="login-subtitle">{message}</p>
                        </div>
                        <div className="cr-status info">
                            {auth_error_text()}
                        </div>
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

    def looks_like_saved_nutrition_day(raw: any) -> bool {
        if not raw {
            return false;
        }
        return String(raw.date_key or "").trim().length > 0;
    }

    def as_nutrition_history(raw: any) -> list {
        if is_listish(raw) and raw.length > 0 and looks_like_saved_nutrition_day(raw[0]) {
            return raw;
        }
        return default_nutrition_history();
    }

    def as_nutrition_targets(raw: any) -> dict {
        if not raw {
            return {};
        }
        calories = num_or_zero(raw.calories_per_day);
        protein = num_or_zero(raw.protein_g);
        carbs = num_or_zero(raw.carbs_g);
        fat = num_or_zero(raw.fat_g);
        if calories <= 0.0 and protein <= 0.0 and carbs <= 0.0 and fat <= 0.0 {
            return {};
        }
        return {
            "calories_per_day": calories,
            "protein_g": protein,
            "carbs_g": carbs,
            "fat_g": fat,
            "notes": String(raw.notes or "").trim()
        };
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

    def round_macro_target(raw: any) -> float {
        value = num_or_zero(raw);
        return Math.round(value * 10.0) / 10.0;
    }

    def macro_activity_multiplier(raw_level: any) -> float {
        level = normalized_profile_choice(raw_level);
        if level == "SEDENTARY" {
            return 1.2;
        }
        if level == "LIGHTLY_ACTIVE" {
            return 1.375;
        }
        if level == "VERY_ACTIVE" {
            return 1.725;
        }
        if level == "ATHLETE" {
            return 1.9;
        }
        return 1.55;
    }

    def macro_sex_bmr_offset(raw_sex: any) -> float {
        sex_val = normalized_profile_choice(raw_sex);
        if sex_val == "FEMALE" {
            return -161.0;
        }
        if sex_val == "OTHER" or sex_val == "PREFER_NOT_TO_SAY" {
            return -78.0;
        }
        return 5.0;
    }

    def macro_goal_calorie_adjustment(raw_goal: any, tdee: float) -> float {
        goal_val = normalized_profile_choice(raw_goal);
        if goal_val == "FAT_LOSS" {
            return -0.2 * tdee;
        }
        if goal_val == "LEAN_BULK" {
            return 0.08 * tdee;
        }
        if goal_val == "MUSCLE_GAIN" {
            return 0.12 * tdee;
        }
        if goal_val == "ENDURANCE_PERFORMANCE" {
            return 0.1 * tdee;
        }
        return 0.0;
    }

    def macro_goal_protein_lb(raw_goal: any) -> float {
        goal_val = normalized_profile_choice(raw_goal);
        if goal_val == "ENDURANCE_PERFORMANCE" {
            return 0.8;
        }
        if goal_val == "MAINTENANCE" {
            return 0.9;
        }
        if goal_val == "LEAN_BULK" {
            return 0.95;
        }
        return 1.0;
    }

    def macro_goal_fat_ratio(raw_goal: any) -> float {
        goal_val = normalized_profile_choice(raw_goal);
        if goal_val == "MUSCLE_GAIN" {
            return 0.25;
        }
        if goal_val == "LEAN_BULK" {
            return 0.28;
        }
        return 0.3;
    }

    def derived_macro_targets_from_profile(profile: dict = {}, source_note: str = "") -> dict {
        if not profile_has_key_info(profile) {
            return {};
        }

        age_num = parseInt(String(profile.age or "").trim());
        height_in = parse_profile_num(String(profile.height or ""), -1.0);
        weight_lb = parse_profile_num(String(profile.weight or ""), -1.0);
        if isNaN(age_num) or age_num <= 0 or height_in <= 0.0 or weight_lb <= 0.0 {
            return {};
        }

        weight_kg = weight_lb * 0.45359237;
        height_cm = height_in * 2.54;
        bmr = (10.0 * weight_kg) + (6.25 * height_cm) - (5.0 * age_num) + macro_sex_bmr_offset(profile.sex);
        activity_multiplier = macro_activity_multiplier(profile.fitness_level);
        tdee = bmr * activity_multiplier;
        calories = tdee + macro_goal_calorie_adjustment(profile.goal, tdee);
        if calories < 1200.0 {
            calories = 1200.0;
        }

        protein_g = weight_lb * macro_goal_protein_lb(profile.goal);
        fat_g = (calories * macro_goal_fat_ratio(profile.goal)) / 9.0;
        carbs_g = (calories - (protein_g * 4.0) - (fat_g * 9.0)) / 4.0;
        if carbs_g < 50.0 {
            carbs_g = 50.0;
            fat_g = (calories - (protein_g * 4.0) - (carbs_g * 4.0)) / 9.0;
        }
        if fat_g < 25.0 {
            fat_g = 25.0;
            carbs_g = (calories - (protein_g * 4.0) - (fat_g * 9.0)) / 4.0;
        }

        notes = "Targets reconstructed from your saved profile on refresh.";
        source_text = String(source_note or "").trim();
        if source_text.length > 0 {
            notes = [notes, " ", source_text].join("");
        }

        return {
            "calories_per_day": round_macro_target(calories),
            "protein_g": round_macro_target(protein_g),
            "carbs_g": round_macro_target(carbs_g),
            "fat_g": round_macro_target(fat_g),
            "notes": notes
        };
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
                    "selected_day_index": safe_day_index(parsed.selected_day_index, history.length),
                    "macro_targets": as_nutrition_targets(parsed.macro_targets)
                };
            }
        } except Exception as _e {
            0;
        }
        return {
            "weekly_history": default_nutrition_history(),
            "selected_day_index": 0,
            "macro_targets": {}
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

    def save_cached_nutrition(weekly: list, idx: int, macro_targets: dict = {}) -> None {
        try {
            localStorage.setItem(
                cache_key("nutrition"),
                JSON.stringify({
                    "weekly_history": weekly,
                    "selected_day_index": idx,
                    "macro_targets": macro_targets
                })
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

    def set_app_state(next_pantry: any, next_history: any, next_idx: any, next_targets: any = {}) -> None {
        pantry_items = as_pantry_items(next_pantry);
        nutrition_history = as_nutrition_history(next_history);
        nutrition_selected_day_index = safe_day_index(next_idx, nutrition_history.length);
        nutrition_targets = as_nutrition_targets(next_targets);
        app_state = {
            "pantry_items": pantry_items,
            "nutrition_history": nutrition_history,
            "nutrition_selected_day_index": nutrition_selected_day_index,
            "nutrition_targets": nutrition_targets
        };
    }

    def ensure_app_state_defaults() -> None {
        history = as_nutrition_history(app_state.nutrition_history);
        set_app_state(
            as_pantry_items(app_state.pantry_items),
            history,
            safe_day_index(app_state.nutrition_selected_day_index, history.length),
            as_nutrition_targets(app_state.nutrition_targets)
        );
    }

    def reset_local_user_state() -> None {
        set_app_state([], default_nutrition_history(), 0, {});
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
        current_history = as_nutrition_history(app_state.nutrition_history);
        current_idx = safe_day_index(app_state.nutrition_selected_day_index, current_history.length);
        next_targets = as_nutrition_targets(app_state.nutrition_targets);
        if Object.keys(next_targets).length == 0 and profile_has_any_data(profile) {
            next_targets = load_cached_nutrition().macro_targets;
        }
        if Object.keys(next_targets).length == 0 and profile_has_key_info(profile) {
            next_targets = derived_macro_targets_from_profile(profile);
        }
        if not profile_has_any_data(profile) {
            next_targets = {};
        }
        set_app_state(as_pantry_items(app_state.pantry_items), current_history, current_idx, next_targets);
        save_cached_nutrition(current_history, current_idx, next_targets);
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
            next_targets = fallback_nutrition.macro_targets;
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
                next_targets = as_nutrition_targets(nutrition_out.macro_targets);
                save_cached_nutrition(next_weekly, next_idx, next_targets);
                nutrition_loaded = true;
            }
            if not nutrition_loaded {
                next_weekly = fallback_nutrition.weekly_history;
                next_idx = fallback_nutrition.selected_day_index;
                next_targets = fallback_nutrition.macro_targets;
            }

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
            if Object.keys(next_targets).length == 0 and profile_has_key_info(profile_payload) {
                next_targets = derived_macro_targets_from_profile(profile_payload);
                save_cached_nutrition(next_weekly, next_idx, next_targets);
            }
            set_app_state(next_pantry, next_weekly, next_idx, next_targets);
            return {"has_profile": has_profile, "profile": profile_payload};
        } except Exception as e {
            fallback_nutrition = load_cached_nutrition();
            fallback_profile = load_cached_profile();
            fallback_targets = fallback_nutrition.macro_targets;
            if Object.keys(fallback_targets).length == 0 and profile_has_key_info(fallback_profile) {
                fallback_targets = derived_macro_targets_from_profile(fallback_profile);
                save_cached_nutrition(
                    fallback_nutrition.weekly_history,
                    fallback_nutrition.selected_day_index,
                    fallback_targets
                );
            }
            set_app_state(
                load_cached_pantry(),
                fallback_nutrition.weekly_history,
                fallback_nutrition.selected_day_index,
                fallback_targets
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
        set_app_state(clean_items, nutrition_cache.weekly_history, nutrition_cache.selected_day_index, nutrition_cache.macro_targets);
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
        targets = as_nutrition_targets(payload.macro_targets);

        save_cached_nutrition(weekly, idx, targets);
        pantry_cache = load_cached_pantry();
        set_app_state(pantry_cache, weekly, idx, targets);
        try {
            out = await call_authenticated_walker(
                "SaveNutritionState",
                {
                    "selected_day_index": idx,
                    "weekly_history": weekly,
                    "macro_targets": targets
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
                safe_day_index(app_state.nutrition_selected_day_index, as_nutrition_history(app_state.nutrition_history).length),
                as_nutrition_targets(app_state.nutrition_targets)
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
        return route_transition_shell("CaloReceipt", "Restoring your workspace and account state.");
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
            <div className="cr-auth-page">
                <div className="cr-auth-layout">
                    <div className="cr-auth-aside">
                        <div>
                            <div className="cr-auth-kicker">Receipt-first planning</div>
                            <h1 className="greeting" style={{"margin": "0 0 0.35rem 0"}}>
                                Build your food system once.
                            </h1>
                            <p className="greeting-sub" style={{"margin": "0"}}>
                                CaloReceipt turns receipts into pantry state, meal ideas, and macro-aware nutrition tracking.
                            </p>
                        </div>
                        <div className="cr-auth-points">
                            <div className="cr-auth-point">
                                <div className="card-title">Receipt to pantry</div>
                                <div className="card-subtitle">Capture receipts, parse grocery items, and keep inventory up to date.</div>
                            </div>
                            <div className="cr-auth-point">
                                <div className="card-title">Profile-driven macros</div>
                                <div className="card-subtitle">Use your measurements and goals to personalize recipes and nutrition targets.</div>
                            </div>
                            <div className="cr-auth-point">
                                <div className="card-title">One shared workspace</div>
                                <div className="card-subtitle">Move cleanly between intake, planning, ranking, and weekly progress.</div>
                            </div>
                        </div>
                    </div>

                    <div className="login-card cr-auth-card">
                        <div className="login-header">
                            <div className="login-logo">
                                <div className="logo-icon">
                                    <svg viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                                    </svg>
                                </div>
                                <span>CaloReceipt</span>
                            </div>
                            <h1 className="login-title">
                                {("Welcome back" if auth_mode == "login" else "Create your account")}
                            </h1>
                            <p className="login-subtitle">
                                {("Sign in to reach your pantry, profile, and recipe workspace." if auth_mode == "login" else "Register first. We will route you straight into profile setup after signup.")}
                            </p>
                        </div>

                        <div className="cr-auth-switch">
                            <button onClick={lambda -> None { auth_mode = "login"; }} className={auth_mode_button_class("login")}>
                                Login
                            </button>
                            <button onClick={lambda -> None { auth_mode = "signup"; }} className={auth_mode_button_class("signup")}>
                                Register
                            </button>
                        </div>

                        <div className="cr-auth-grid">
                            <div className="form-group">
                                <label className="form-label">Email Address</label>
                                <input
                                    value={auth_email}
                                    onChange={lambda e: any -> None { auth_email = e.target.value; }}
                                    placeholder="you@example.com"
                                    className="form-input"
                                />
                            </div>
                            <div className="form-group">
                                <label className="form-label">Password</label>
                                <input
                                    type="password"
                                    value={auth_password}
                                    onChange={lambda e: any -> None { auth_password = e.target.value; }}
                                    placeholder="Enter your password"
                                    className="form-input"
                                />
                            </div>
                        </div>

                        <div className="cr-auth-actions">
                            <button onClick={(do_login if auth_mode == "login" else do_signup)} className={("btn " + ("cr-btn-accent" if auth_mode == "login" else "cr-btn-success"))}>
                                {("Sign In" if auth_mode == "login" else "Create Account")}
                            </button>

                            <div className="login-divider">
                                <span>or continue with</span>
                            </div>

                            <button
                                onClick={lambda -> None { start_sso("google"); }}
                                className={("btn " + ("btn-secondary" if sso_provider_configured("google") else "cr-btn-warning"))}
                            >
                                {("Continue with Google" if auth_mode == "login" else "Register with Google")}
                            </button>
                            <div className="cr-auth-provider-copy">
                                {("Google sign-in is ready." if sso_provider_configured("google") else sso_setup_message("google"))}
                            </div>

                            <button
                                onClick={lambda -> None { start_sso("apple"); }}
                                className={("btn " + ("btn-secondary" if sso_provider_configured("apple") else "cr-btn-warning"))}
                            >
                                {("Continue with Apple" if auth_mode == "login" else "Register with Apple")}
                            </button>
                            <div className="cr-auth-provider-copy">
                                {("Apple sign-in is ready." if sso_provider_configured("apple") else sso_setup_message("apple"))}
                            </div>
                        </div>

                        <div className="cr-status info">
                            {auth_error_text()}
                        </div>
                    </div>
                </div>
            </div>;
    }

    if requires_profile_setup {
        return
            <div className="cr-onboarding-page">
                <div className="cr-onboarding-container">
                    <div className="cr-onboarding-hero">
                        <div className="cr-onboarding-copy">
                            <div className="cr-auth-kicker">Profile setup</div>
                            <h1 className="greeting" style={{"margin": "0 0 0.35rem 0"}}>Finish Your Profile</h1>
                            <p className="greeting-sub" style={{"margin": "0"}}>
                                One short survey before you enter the dashboard. These fields tune pantry planning, recipe generation, and macro targets.
                            </p>
                        </div>
                        <div className="cr-page-actions">
                            <div className="cr-chip warning">Step Required</div>
                            <div className="cr-chip info">{display_identity()}</div>
                        </div>
                    </div>

                    <div className="cr-status warning">
                        {auth_error_text()}
                    </div>

                    <div className="cr-section-grid">
                        <div className="cr-form-card">
                            <div>
                                <div className="card-title">About You</div>
                                <div className="card-subtitle">Tell us the basics we need for your profile.</div>
                            </div>
                            <div className="cr-form-row">
                                <div className="form-group">
                                    <label className="form-label">Name</label>
                                    <input value={signup_name} onChange={lambda e: any -> None { signup_name = e.target.value; }} placeholder="Preferred name" />
                                </div>
                                <div className="cr-form-row two">
                                    <div className="form-group">
                                        <label className="form-label">Age</label>
                                        <input value={signup_age} onChange={lambda e: any -> None { signup_age = e.target.value; }} placeholder="Years" />
                                    </div>
                                    <div className="form-group">
                                        <label className="form-label">Sex</label>
                                        <select value={signup_sex} onChange={lambda e: any -> None { signup_sex = e.target.value; }}>
                                            <option value="MALE">Male</option>
                                            <option value="FEMALE">Female</option>
                                            <option value="OTHER">Other</option>
                                            <option value="PREFER_NOT_TO_SAY">Prefer not to say</option>
                                        </select>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div className="cr-form-card">
                            <div>
                                <div className="card-title">Body Metrics</div>
                                <div className="card-subtitle">We use these to tailor calories, macros, and portion guidance.</div>
                            </div>
                            <div className="cr-form-row">
                                <div className="form-group">
                                    <label className="form-label">Height (in)</label>
                                    <input value={signup_height} onChange={lambda e: any -> None { signup_height = e.target.value; }} placeholder="70" />
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Current Weight (lb)</label>
                                    <input value={signup_weight} onChange={lambda e: any -> None { signup_weight = e.target.value; }} placeholder="170" />
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Goal Weight (lb)</label>
                                    <input value={signup_goal_weight} onChange={lambda e: any -> None { signup_goal_weight = e.target.value; }} placeholder="Optional" />
                                </div>
                            </div>
                        </div>

                        <div className="cr-form-card">
                            <div>
                                <div className="card-title">Goals And Preferences</div>
                                <div className="card-subtitle">Set activity level, overall goal, restrictions, and allergies.</div>
                            </div>
                            <div className="cr-form-row">
                                <div className="form-group">
                                    <label className="form-label">Fitness Level</label>
                                    <select value={signup_fitness_level} onChange={lambda e: any -> None { signup_fitness_level = e.target.value; }}>
                                        <option value="SEDENTARY">Sedentary</option>
                                        <option value="LIGHTLY_ACTIVE">Lightly active</option>
                                        <option value="MODERATELY_ACTIVE">Moderately active</option>
                                        <option value="VERY_ACTIVE">Very active</option>
                                        <option value="ATHLETE">Athlete</option>
                                    </select>
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Overall Goal</label>
                                    <select value={signup_goal} onChange={lambda e: any -> None { signup_goal = e.target.value; }}>
                                        <option value="FAT_LOSS">Fat loss</option>
                                        <option value="MAINTENANCE">Maintenance</option>
                                        <option value="LEAN_BULK">Lean bulk</option>
                                        <option value="MUSCLE_GAIN">Muscle gain</option>
                                        <option value="ENDURANCE_PERFORMANCE">Endurance performance</option>
                                    </select>
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Dietary Restrictions</label>
                                    <input value={signup_dietary_notes} onChange={lambda e: any -> None { signup_dietary_notes = e.target.value; }} placeholder="Comma-separated, e.g. vegetarian, halal" />
                                </div>
                                <div className="form-group">
                                    <label className="form-label">Allergies</label>
                                    <input value={signup_allergy_notes} onChange={lambda e: any -> None { signup_allergy_notes = e.target.value; }} placeholder="Comma-separated, e.g. peanuts, shellfish" />
                                </div>
                            </div>
                        </div>
                    </div>

                    <div className="cr-form-actions">
                        <button onClick={complete_profile_setup} className="btn cr-btn-success">
                            Save And Enter Dashboard
                        </button>
                        <button onClick={do_logout} className="btn cr-btn-danger">
                            Log Out
                        </button>
                    </div>
                </div>
            </div>;
    }

    return
        <div className="app-container cr-app-shell">
            <nav className="top-nav">
                <div className="nav-container cr-nav-container">
                    <div className="cr-nav-left">
                        <button onClick={lambda -> None { set_tab("dashboard"); }} className="logo cr-logo-button">
                            <div className="logo-icon">
                                <svg viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                                </svg>
                            </div>
                            CaloReceipt
                        </button>
                        <div className="cr-nav-menu">
                            <button onClick={lambda -> None { set_tab("receipt"); }} className={nav_link_class("receipt")}>Receipt Upload</button>
                            <button onClick={lambda -> None { set_tab("dashboard"); }} className={nav_link_class("dashboard")}>Dashboard</button>
                            <button onClick={lambda -> None { set_tab("profile"); }} className={nav_link_class("profile")}>User Profile</button>
                            <button onClick={lambda -> None { set_tab("recipes"); }} className={nav_link_class("recipes")}>Recipes</button>
                            <button onClick={lambda -> None { set_tab("nutrition"); }} className={nav_link_class("nutrition")}>Nutrition</button>
                        </div>
                    </div>
                    <div className="nav-right">
                        <div className="user-menu">
                            <div className="user-avatar">{user_initials()}</div>
                            <span className="user-name">{display_identity()}</span>
                        </div>
                        <button onClick={do_logout} className="btn cr-btn-danger">Log Out</button>
                    </div>
                </div>
            </nav>

            <main className="main-content cr-main-content">
                <div className="page-header cr-page-header">
                    <div>
                        <h1 className="greeting">{greeting_text()}</h1>
                        <p className="greeting-sub">{tab_summary(active_tab)}</p>
                    </div>
                    <div className="cr-page-actions">
                        <div className="cr-chip success">Signed In</div>
                        <div className="cr-chip info">{tab_label(active_tab)}</div>
                    </div>
                </div>

                <div className="stats-grid cr-stats-grid">
                    <div className="cr-stat-card">
                        <div className="stat-label">Pantry Items</div>
                        <div className="stat-value">{String(as_pantry_items(app_state.pantry_items).length)}</div>
                        <div className="card-subtitle">Current inventory synced from receipts and pantry edits.</div>
                    </div>
                    <div className="cr-stat-card">
                        <div className="stat-label">Nutrition Days</div>
                        <div className="stat-value">{String(as_nutrition_history(app_state.nutrition_history).length)}</div>
                        <div className="card-subtitle">Weekly history entries available in the nutrition tab.</div>
                    </div>
                    <div className="cr-stat-card">
                        <div className="stat-label">Profile Identity</div>
                        <div className="stat-value">{user_initials()}</div>
                        <div className="card-subtitle">{display_identity()}</div>
                    </div>
                    <div className="cr-stat-card">
                        <div className="stat-label">Active Workspace</div>
                        <div className="stat-value">{tab_label(active_tab)}</div>
                        <div className="card-subtitle">Jump between intake, planning, recipes, and progress.</div>
                    </div>
                </div>

                <div className="cr-panel-stack">
                    <div className="cr-tab-frame" style={{"display": ("block" if active_tab == "receipt" else "none")}}>
                        <ReceiptUploadTab
                            shared_state={app_state}
                            on_auth_error={handle_auth_required}
                            on_pantry_change={save_pantry_state}
                            is_active={active_tab == "receipt"}
                        />
                    </div>
                    <div className="cr-tab-frame" style={{"display": ("block" if active_tab == "dashboard" else "none")}}>
                        <DashboardAiTab on_auth_error={handle_auth_required} />
                    </div>
                    <div className="cr-tab-frame" style={{"display": ("block" if active_tab == "profile" else "none")}}>
                        <UserProfileTab
                            on_auth_error={handle_auth_required}
                            on_profile_change={handle_profile_change}
                            user_storage_key={active_user_key}
                        />
                    </div>
                    <div className="cr-tab-frame" style={{"display": ("block" if active_tab == "recipes" else "none")}}>
                        <RecipesTab
                            shared_state={app_state}
                            on_auth_error={handle_auth_required}
                            on_pantry_change={save_pantry_state}
                            on_nutrition_change={save_nutrition_state}
                        />
                    </div>
                    <div className="cr-tab-frame" style={{"display": ("block" if active_tab == "nutrition" else "none")}}>
                        <NutritionTab
                            shared_state={app_state}
                            on_nutrition_change={save_nutrition_state}
                            on_auth_error={handle_auth_required}
                            is_hydrating={is_hydrating_user_state}
                        />
                    </div>
                </div>
            </main>
        </div>;
}
