sv import from user {
    GenerateUserMacroNeeds
}

def:pub NutritionTab(
    shared_state: dict = {},
    on_nutrition_change: any = None,
    on_auth_error: any = None,
    is_hydrating: bool = false
) -> JsxElement {
    has selected_day_index: int = 0;
    has weekly_history: list = [];
    has macro_targets: dict = {};
    has view_mode: str = "day";
    has status_text: str = "Macro progress fills in as you mark recipes made.";
    has loading_targets: bool = false;
    has did_try_target_load: bool = false;

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

    def to_num(raw: any, fallback: float = 0.0) -> float {
        parsed = parseFloat(String(raw or "0"));
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def to_int(raw: any, fallback: int = 0) -> int {
        parsed = parseInt(String(raw or "0"));
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def round_two(value: float) -> float {
        return Math.round(value * 100.0) / 100.0;
    }

    def now_ms() -> int {
        now_obj = Reflect.construct(Date, []);
        return parseInt(now_obj.getTime().toString());
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

    def maybe_trigger_auth_error(text: str) -> None {
        if on_auth_error and is_auth_error_text(text) {
            on_auth_error("Session expired. Please sign in again.");
        }
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
        anchor_value = (anchor_raw if (not isNaN(anchor_raw) and anchor_raw > 0) else now_ms());
        start = Reflect.construct(Date, [anchor_value]);
        start.setHours(0);
        start.setMinutes(0);
        start.setSeconds(0);
        start.setMilliseconds(0);
        offset = ((start.getDay() + 6) % 7);
        start.setDate(start.getDate() - offset);
        return start;
    }

    def build_empty_day(date_obj: any) -> dict {
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

    def build_week_history(anchor_ms: any = None) -> list {
        week_start = start_of_week_date(anchor_ms);
        history: list = [];
        for idx=0 to idx<7 by idx+=1 {
            day_date = Reflect.construct(Date, [week_start.getTime()]);
            day_date.setDate(week_start.getDate() + idx);
            history = history.concat([build_empty_day(day_date)]);
        }
        return history;
    }

    def looks_like_saved_day(raw: any) -> bool {
        if not raw {
            return false;
        }
        return String(raw.date_key or "").trim().length > 0;
    }

    def normalized_recipe_entry(raw: any) -> dict {
        return {
            "recipe_id": String(raw.recipe_id or "").trim(),
            "title": String(raw.title or "Recipe").trim(),
            "calories": to_num(raw.calories, 0.0),
            "protein_g": to_num(raw.protein_g, 0.0),
            "carbs_g": to_num(raw.carbs_g, 0.0),
            "fat_g": to_num(raw.fat_g, 0.0),
            "meal_type": String(raw.meal_type or "").trim().toLowerCase(),
            "made_at_ms": to_int(raw.made_at_ms, 0)
        };
    }

    def meal_label(raw: any) -> str {
        meal_text = String(raw or "").trim().toLowerCase();
        if meal_text == "breakfast" {
            return "Breakfast";
        }
        if meal_text == "lunch" {
            return "Lunch";
        }
        if meal_text == "dinner" {
            return "Dinner";
        }
        if meal_text == "snack" {
            return "Snack";
        }
        return "";
    }

    def normalized_day_entry(raw: any, fallback_date: any = None) -> dict {
        date_obj = fallback_date;
        if date_obj == None {
            date_obj = Reflect.construct(Date, []);
        }
        date_key = String(raw.date_key or "").trim();
        day_name = String(raw.day or "").trim();
        label_text = String(raw.label or "").trim();
        if date_key == "" {
            date_key = nutrition_date_key(date_obj);
        }
        if day_name == "" {
            day_name = nutrition_day_name_from_index(date_obj.getDay());
        }
        if label_text == "" {
            label_text = nutrition_day_label(date_obj);
        }
        entries: list = [];
        if is_listish(raw.entries) {
            entries = raw.entries.map(
                lambda recipe_item: dict -> dict { return normalized_recipe_entry(recipe_item); }
            );
        }
        return {
            "date_key": date_key,
            "day": day_name,
            "label": label_text,
            "calories_consumed": round_two(to_num(raw.calories_consumed, 0.0)),
            "protein_consumed": round_two(to_num(raw.protein_consumed, 0.0)),
            "carbs_consumed": round_two(to_num(raw.carbs_consumed, 0.0)),
            "fat_consumed": round_two(to_num(raw.fat_consumed, 0.0)),
            "entries": entries
        };
    }

    def history_for_anchor(raw: any, anchor_ms: any = None) -> list {
        base_history = build_week_history(anchor_ms);
        if not is_listish(raw) or raw.length == 0 or not looks_like_saved_day(raw[0]) {
            return base_history;
        }

        saved_by_key: dict = {};
        for day_item in raw {
            normalized = normalized_day_entry(day_item, None);
            key = String(normalized.date_key or "").trim();
            if key.length > 0 {
                saved_by_key[key] = normalized;
            }
        }

        merged: list = [];
        for base_day in base_history {
            key = String(base_day.date_key or "").trim();
            saved = saved_by_key[key] or None;
            if saved != None {
                merged = merged.concat([normalized_day_entry(saved, Reflect.construct(Date, [start_of_week_date(anchor_ms).getTime()]))]);
            } else {
                merged = merged.concat([base_day]);
            }
        }
        return merged;
    }

    def safe_day_index(raw: any, history: list) -> int {
        if history.length == 0 {
            return 0;
        }
        idx = parseInt(String(raw or "0"));
        if not isNaN(idx) and idx >= 0 and idx < history.length {
            return idx;
        }
        today_key = nutrition_date_key(Reflect.construct(Date, []));
        today_idx = history.findIndex(
            lambda item: dict -> bool { return String(item.date_key or "") == today_key; }
        );
        if today_idx >= 0 {
            return today_idx;
        }
        return 0;
    }

    def current_calendar_day_index(history: list) -> int {
        if history.length == 0 {
            return 0;
        }
        today_key = nutrition_date_key(Reflect.construct(Date, []));
        today_idx = history.findIndex(
            lambda item: dict -> bool { return String(item.date_key or "") == today_key; }
        );
        if today_idx >= 0 {
            return today_idx;
        }
        return safe_day_index(-1, history);
    }

    def normalized_macro_targets(raw: any) -> dict {
        if not raw {
            return {};
        }
        calories = round_two(to_num(raw.calories_per_day, 0.0));
        protein = round_two(to_num(raw.protein_g, 0.0));
        carbs = round_two(to_num(raw.carbs_g, 0.0));
        fat = round_two(to_num(raw.fat_g, 0.0));
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

    def push_nutrition_state() -> None {
        shared_state.nutrition_history = weekly_history;
        shared_state.nutrition_selected_day_index = selected_day_index;
        shared_state.nutrition_targets = macro_targets;
        if on_nutrition_change and not is_hydrating {
            on_nutrition_change({
                "weekly_history": weekly_history,
                "selected_day_index": selected_day_index,
                "macro_targets": macro_targets
            });
        }
    }

    async def ensure_macro_targets() -> None {
        if loading_targets or did_try_target_load or Object.keys(visible_targets()).length > 0 {
            return;
        }
        did_try_target_load = true;
        loading_targets = true;
        status_text = "Loading macro targets from your profile...";
        try {
            result = root spawn GenerateUserMacroNeeds();
            out = first_report_payload(result);
            if out and out.ok {
                macro_targets = normalized_macro_targets(out);
                if Object.keys(macro_targets).length > 0 {
                    status_text = "Macro targets loaded from your profile.";
                    push_nutrition_state();
                } else {
                    status_text = "Profile targets are not ready yet.";
                }
            } elif out and out.error {
                err_text = String(out.error or "Unable to load macro targets.");
                status_text = "Could not load macro targets: " + err_text;
                maybe_trigger_auth_error(err_text);
            } else {
                status_text = "Could not load macro targets.";
            }
        } except Exception as e {
            err_text = e.toString();
            status_text = "Could not load macro targets: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading_targets = false;
    }

    async can with entry {
        weekly_history = history_for_anchor(shared_state.nutrition_history, now_ms());
        selected_day_index = current_calendar_day_index(weekly_history);
        macro_targets = visible_targets();
        push_nutrition_state();
        if Object.keys(visible_targets()).length == 0 {
            await ensure_macro_targets();
        }
    }

    def visible_history() -> list {
        if is_listish(shared_state.nutrition_history) and shared_state.nutrition_history.length > 0 and looks_like_saved_day(shared_state.nutrition_history[0]) {
            return shared_state.nutrition_history;
        }
        if weekly_history.length > 0 {
            return weekly_history;
        }
        return build_week_history(now_ms());
    }

    def visible_targets() -> dict {
        shared_targets = normalized_macro_targets(shared_state.nutrition_targets);
        if Object.keys(shared_targets).length > 0 {
            return shared_targets;
        }
        return macro_targets;
    }

    def visible_selected_index(history: list = []) -> int {
        source_history = history;
        if source_history.length == 0 {
            source_history = visible_history();
        }
        shared_idx = safe_day_index(shared_state.nutrition_selected_day_index, source_history);
        if shared_idx >= 0 and shared_idx < source_history.length {
            return shared_idx;
        }
        return safe_day_index(selected_day_index, source_history);
    }

    def selected_day() -> dict {
        history = visible_history();
        safe_idx = visible_selected_index(history);
        return history[safe_idx];
    }

    def consumed_value(metric_key: str, day_item: dict = {}) -> float {
        source = (day_item if Object.keys(day_item).length > 0 else selected_day());
        return round_two(to_num(source[metric_key], 0.0));
    }

    def target_value(metric_key: str) -> float {
        targets = visible_targets();
        if metric_key == "calories_consumed" {
            return round_two(to_num(targets.calories_per_day, 0.0));
        }
        if metric_key == "protein_consumed" {
            return round_two(to_num(targets.protein_g, 0.0));
        }
        if metric_key == "carbs_consumed" {
            return round_two(to_num(targets.carbs_g, 0.0));
        }
        if metric_key == "fat_consumed" {
            return round_two(to_num(targets.fat_g, 0.0));
        }
        return 0.0;
    }

    def current_consumed(metric_key: str) -> float {
        if view_mode == "week" {
            total = 0.0;
            for day_item in visible_history() {
                total = total + consumed_value(metric_key, day_item);
            }
            return round_two(total);
        }
        return consumed_value(metric_key, selected_day());
    }

    def current_target(metric_key: str) -> float {
        base = target_value(metric_key);
        if view_mode == "week" {
            return round_two(base * visible_history().length);
        }
        return base;
    }

    def display_percent(consumed: float, target: float) -> int {
        if target <= 0.0 {
            return 0;
        }
        return parseInt(Math.round((consumed * 100.0) / target).toString());
    }

    def wheel_percent(consumed: float, target: float) -> int {
        shown = display_percent(consumed, target);
        if shown < 0 {
            return 0;
        }
        if shown > 100 {
            return 100;
        }
        return shown;
    }

    def display_amount(value: float, suffix: str = "") -> str {
        rounded = round_two(value);
        if Math.abs(rounded - Math.round(rounded)) < 0.01 {
            return [String(Math.round(rounded)), suffix].join("");
        }
        return [rounded.toFixed(1), suffix].join("");
    }

    def current_view_title() -> str {
        if view_mode == "week" {
            return "This Week";
        }
        return String(selected_day().label or "Today");
    }

    def current_view_subtitle() -> str {
        if view_mode == "week" {
            return "Weekly totals against your seven-day targets";
        }
        return "Today's totals against your daily targets";
    }

    def metric_unit(metric_key: str) -> str {
        if metric_key == "calories_consumed" {
            return " cal";
        }
        return " g";
    }

    def metric_label(metric_key: str) -> str {
        if metric_key == "calories_consumed" {
            return "Calories";
        }
        if metric_key == "protein_consumed" {
            return "Protein";
        }
        if metric_key == "carbs_consumed" {
            return "Carbs";
        }
        return "Fat";
    }

    def recipe_entries_for_selected_day() -> list {
        if not is_listish(selected_day().entries) {
            return [];
        }
        return selected_day().entries;
    }

    def week_average_percent(day_item: dict) -> int {
        calories_pct = display_percent(consumed_value("calories_consumed", day_item), target_value("calories_consumed"));
        protein_pct = display_percent(consumed_value("protein_consumed", day_item), target_value("protein_consumed"));
        carbs_pct = display_percent(consumed_value("carbs_consumed", day_item), target_value("carbs_consumed"));
        fat_pct = display_percent(consumed_value("fat_consumed", day_item), target_value("fat_consumed"));
        return parseInt(Math.round((calories_pct + protein_pct + carbs_pct + fat_pct) / 4.0).toString());
    }

    return
        <div className="card cr-module-shell" style={{"display": "grid", "gap": "14px"}}>
            <div>
                <h2 style={{"margin": "0"}}>Nutrition Progress</h2>
                <p style={{"margin": "6px 0 0 0", "opacity": "0.78", "lineHeight": "1.45"}}>
                    Track how your cooked recipes fill your daily and weekly macro targets with a real progress wheel instead of the old placeholder demo.
                </p>
            </div>

            <div className="cr-status info">
                {[( "Working... " if loading_targets else "Ready. " ), status_text].join("")}
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                <button
                    onClick={lambda -> None { view_mode = "day"; }}
                    style={{
                        "padding": "8px 12px",
                        "borderRadius": "999px",
                        "border": ("1px solid #0f766e" if view_mode == "day" else "1px solid #cbd5e1"),
                        "background": ("#ccfbf1" if view_mode == "day" else "#ffffff"),
                        "fontWeight": "800",
                        "color": ("#115e59" if view_mode == "day" else "#334155")
                    }}
                >
                    Day View
                </button>
                <button
                    onClick={lambda -> None { view_mode = "week"; }}
                    style={{
                        "padding": "8px 12px",
                        "borderRadius": "999px",
                        "border": ("1px solid #0f766e" if view_mode == "week" else "1px solid #cbd5e1"),
                        "background": ("#ccfbf1" if view_mode == "week" else "#ffffff"),
                        "fontWeight": "800",
                        "color": ("#115e59" if view_mode == "week" else "#334155")
                    }}
                >
                    Week View
                </button>
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                {visible_history().map(
                    lambda day_item: dict -> JsxElement { return
                        <button
                            key={String(day_item.date_key or day_item.day)}
                            onClick={lambda -> None {
                                history_rows = visible_history();
                                next_idx = history_rows.findIndex(
                                    lambda row: dict -> bool { return String(row.date_key or "") == String(day_item.date_key or ""); }
                                );
                                if next_idx >= 0 {
                                    selected_day_index = next_idx;
                                    shared_state.nutrition_selected_day_index = next_idx;
                                    push_nutrition_state();
                                }
                            }}
                            style={{
                                "padding": "8px 10px",
                                "borderRadius": "999px",
                                "border": "1px solid #cbd5e1",
                                "background": ("#dbeafe" if String(selected_day().date_key or "") == String(day_item.date_key or "") else "#ffffff"),
                                "fontWeight": "700"
                            }}
                        >
                            {String(day_item.day or "")}
                        </button>; }
                )}
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(320px, 1fr))", "gap": "14px", "alignItems": "start"}}>
                <div style={{"border": "1px solid #dbeafe", "borderRadius": "18px", "padding": "16px", "background": "linear-gradient(145deg, #eff6ff, #f8fafc)", "display": "grid", "gap": "14px"}}>
                    <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "8px", "flexWrap": "wrap"}}>
                        <div>
                            <div style={{"fontSize": "0.82rem", "fontWeight": "800", "letterSpacing": "0.08em", "textTransform": "uppercase", "color": "#0f766e"}}>{current_view_title()}</div>
                            <div style={{"fontSize": "0.95rem", "opacity": "0.78", "marginTop": "4px"}}>{current_view_subtitle()}</div>
                        </div>
                        <div style={{"padding": "6px 10px", "borderRadius": "999px", "border": "1px solid #bfdbfe", "background": "#ffffff", "fontWeight": "800", "color": "#1d4ed8"}}>
                            {String(display_percent(current_consumed("calories_consumed"), current_target("calories_consumed")))}% calories
                        </div>
                    </div>

                    <div className="cr-nutrition-wheel-shell">
                        <div className="cr-nutrition-wheel-halo" />

                        <div className="cr-nutrition-wheel-badge top">
                            <div style={{"fontSize": "0.72rem", "fontWeight": "800", "letterSpacing": "0.06em", "textTransform": "uppercase", "color": "#0284c7"}}>Protein</div>
                            <div style={{"fontSize": "1rem", "fontWeight": "800"}}>{String(display_percent(current_consumed("protein_consumed"), current_target("protein_consumed")))}%</div>
                        </div>
                        <div className="cr-nutrition-wheel-badge right">
                            <div style={{"fontSize": "0.72rem", "fontWeight": "800", "letterSpacing": "0.06em", "textTransform": "uppercase", "color": "#ea580c"}}>Carbs</div>
                            <div style={{"fontSize": "1rem", "fontWeight": "800"}}>{String(display_percent(current_consumed("carbs_consumed"), current_target("carbs_consumed")))}%</div>
                        </div>
                        <div className="cr-nutrition-wheel-badge left">
                            <div style={{"fontSize": "0.72rem", "fontWeight": "800", "letterSpacing": "0.06em", "textTransform": "uppercase", "color": "#7c3aed"}}>Fat</div>
                            <div style={{"fontSize": "1rem", "fontWeight": "800"}}>{String(display_percent(current_consumed("fat_consumed"), current_target("fat_consumed")))}%</div>
                        </div>
                        <div className="cr-nutrition-wheel-badge bottom wide">
                            <div style={{"fontSize": "0.72rem", "fontWeight": "800", "letterSpacing": "0.06em", "textTransform": "uppercase", "color": "#059669"}}>Calories</div>
                            <div style={{"fontSize": "1rem", "fontWeight": "800"}}>{String(display_percent(current_consumed("calories_consumed"), current_target("calories_consumed")))}%</div>
                        </div>

                        <div className="cr-nutrition-wheel-outer" style={{"background": ["conic-gradient(#0ea5e9 0deg ", String(wheel_percent(current_consumed("protein_consumed"), current_target("protein_consumed")) * 3.6), "deg, rgba(191, 219, 254, 0.35) 0deg 360deg)"].join("")}}>
                            <div className="cr-nutrition-wheel-gap lg">
                                <div className="cr-nutrition-wheel-middle" style={{"background": ["conic-gradient(#f97316 0deg ", String(wheel_percent(current_consumed("carbs_consumed"), current_target("carbs_consumed")) * 3.6), "deg, rgba(254, 215, 170, 0.45) 0deg 360deg)"].join("")}}>
                                    <div className="cr-nutrition-wheel-gap md">
                                        <div className="cr-nutrition-wheel-inner" style={{"background": ["conic-gradient(#8b5cf6 0deg ", String(wheel_percent(current_consumed("fat_consumed"), current_target("fat_consumed")) * 3.6), "deg, rgba(221, 214, 254, 0.55) 0deg 360deg)"].join("")}}>
                                            <div className="cr-nutrition-wheel-center">
                                                <div style={{"fontSize": "0.7rem", "fontWeight": "800", "letterSpacing": "0.08em", "textTransform": "uppercase", "color": "#0f766e"}}>{("Day" if view_mode == "day" else "Week")}</div>
                                                <div style={{"fontSize": "1.15rem", "fontWeight": "900", "lineHeight": "1.05"}}>{display_amount(current_consumed("calories_consumed"))}</div>
                                                <div style={{"fontSize": "0.76rem", "opacity": "0.72"}}>of {display_amount(current_target("calories_consumed"))} cal</div>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {(
                        <div style={{"padding": "10px 12px", "borderRadius": "12px", "border": "1px solid #fde68a", "background": "#fffbeb", "lineHeight": "1.45"}}>
                            Complete your profile or wait for macro targets to load before percentages can be calculated accurately.
                        </div>
                    ) if Object.keys(visible_targets()).length == 0 else None}
                </div>

                <div style={{"display": "grid", "gap": "10px"}}>
                    {[
                        {"key": "calories_consumed", "accent": "#10b981", "bg": "#ecfdf5", "border": "#a7f3d0"},
                        {"key": "protein_consumed", "accent": "#0ea5e9", "bg": "#eff6ff", "border": "#bfdbfe"},
                        {"key": "carbs_consumed", "accent": "#f97316", "bg": "#fff7ed", "border": "#fdba74"},
                        {"key": "fat_consumed", "accent": "#8b5cf6", "bg": "#f5f3ff", "border": "#c4b5fd"}
                    ].map(
                        lambda metric: dict -> JsxElement {
                            consumed = current_consumed(metric.key);
                            target = current_target(metric.key);
                            shown_pct = display_percent(consumed, target);
                            return
                                <div key={metric.key} style={{"border": ["1px solid ", metric.border].join(""), "borderRadius": "14px", "padding": "12px", "background": metric.bg, "display": "grid", "gap": "8px"}}>
                                    <div style={{"display": "flex", "justifyContent": "space-between", "gap": "8px", "alignItems": "baseline"}}>
                                        <div style={{"fontWeight": "800", "color": metric.accent}}>{metric_label(metric.key)}</div>
                                        <div style={{"fontSize": "1.05rem", "fontWeight": "900"}}>{String(shown_pct)}%</div>
                                    </div>
                                    <div style={{"fontSize": "1.15rem", "fontWeight": "800"}}>
                                        {display_amount(consumed, metric_unit(metric.key))} / {display_amount(target, metric_unit(metric.key))}
                                    </div>
                                    <div style={{"height": "10px", "borderRadius": "999px", "background": "rgba(148, 163, 184, 0.18)", "overflow": "hidden"}}>
                                        <div
                                            style={{
                                                "height": "100%",
                                                "width": [String(wheel_percent(consumed, target)), "%"].join(""),
                                                "background": ["linear-gradient(90deg, ", metric.accent, " 0%, ", metric.accent, " 100%)"].join("")
                                            }}
                                        />
                                    </div>
                                </div>;
                        }
                    )}
                </div>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(280px, 1fr))", "gap": "14px"}}>
                <div style={{"border": "1px solid var(--border-color)", "borderRadius": "14px", "padding": "14px", "background": "var(--bg-surface)", "display": "grid", "gap": "10px"}}>
                    <div>
                        <h3 style={{"margin": "0"}}>Week Breakdown</h3>
                        <div style={{"marginTop": "4px", "opacity": "0.76"}}>A quick read on how each day stacked up against your targets.</div>
                    </div>
                    {visible_history().map(
                        lambda day_item: dict -> JsxElement {
                            avg_pct = week_average_percent(day_item);
                            return
                                <div key={String(day_item.date_key or "")} style={{"display": "grid", "gap": "5px"}}>
                                    <div style={{"display": "flex", "justifyContent": "space-between", "gap": "8px", "fontSize": "0.92rem"}}>
                                        <span style={{"fontWeight": ("800" if String(selected_day().date_key or "") == String(day_item.date_key or "") else "700")}}>
                                            {String(day_item.label or day_item.day or "")}
                                        </span>
                                        <span>{String(avg_pct)}% avg</span>
                                    </div>
                                    <div style={{"height": "10px", "borderRadius": "999px", "background": "rgba(148, 163, 184, 0.18)", "overflow": "hidden"}}>
                                        <div
                                            style={{
                                                "height": "100%",
                                                "width": [String((100 if avg_pct > 100 else (0 if avg_pct < 0 else avg_pct))), "%"].join(""),
                                                "background": "linear-gradient(90deg, #0ea5e9 0%, #8b5cf6 45%, #10b981 100%)"
                                            }}
                                        />
                                    </div>
                                </div>;
                        }
                    )}
                </div>

                <div style={{"border": "1px solid var(--border-color)", "borderRadius": "14px", "padding": "14px", "background": "var(--bg-surface)", "display": "grid", "gap": "10px"}}>
                    <div>
                        <h3 style={{"margin": "0"}}>{[String(selected_day().label or selected_day().day or "Selected Day"), " Recipes"].join("")}</h3>
                        <div style={{"marginTop": "4px", "opacity": "0.76"}}>
                            Every time you mark a recipe as made, its totals are logged here and added into the wheel.
                        </div>
                    </div>
                    {(
                        <div style={{"opacity": "0.76", "lineHeight": "1.45"}}>
                            No recipes have been logged for this day yet. Use the Recipes tab and mark a meal as made to start filling the wheel.
                        </div>
                    ) if recipe_entries_for_selected_day().length == 0 else (
                        recipe_entries_for_selected_day().map(
                            lambda recipe_item: dict -> JsxElement { return
                                <div key={[String(recipe_item.recipe_id or ""), String(recipe_item.made_at_ms or 0), String(recipe_item.title or "")].join("-")} style={{"border": "1px solid #dbeafe", "borderRadius": "12px", "padding": "10px", "background": "#f8fbff", "display": "grid", "gap": "6px"}}>
                                    <div style={{"display": "flex", "justifyContent": "space-between", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                                        <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                                            <div style={{"fontWeight": "800"}}>{String(recipe_item.title or "Recipe")}</div>
                                            {(
                                                <span style={{"padding": "4px 8px", "borderRadius": "999px", "border": "1px solid #bfdbfe", "background": "#eff6ff", "color": "#1d4ed8", "fontWeight": "800", "fontSize": "0.78rem"}}>
                                                    {meal_label(recipe_item.meal_type)}
                                                </span>
                                            ) if meal_label(recipe_item.meal_type).length > 0 else None}
                                        </div>
                                        <div style={{"fontSize": "0.84rem", "opacity": "0.72"}}>
                                            {(
                                                Reflect.construct(Date, [to_int(recipe_item.made_at_ms, 0)]).toLocaleTimeString([], {"hour": "numeric", "minute": "2-digit"})
                                                if to_int(recipe_item.made_at_ms, 0) > 0
                                                else ""
                                            )}
                                        </div>
                                    </div>
                                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(2, minmax(0, 1fr))", "gap": "6px", "fontSize": "0.92rem"}}>
                                        <div>Calories: {display_amount(to_num(recipe_item.calories, 0.0), " cal")}</div>
                                        <div>Protein: {display_amount(to_num(recipe_item.protein_g, 0.0), " g")}</div>
                                        <div>Carbs: {display_amount(to_num(recipe_item.carbs_g, 0.0), " g")}</div>
                                        <div>Fat: {display_amount(to_num(recipe_item.fat_g, 0.0), " g")}</div>
                                    </div>
                                </div>; }
                        )
                    )}
                </div>
            </div>
        </div>;
}
