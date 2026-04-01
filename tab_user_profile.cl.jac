sv import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile
}

def:pub UserProfileTab(
    on_auth_error: any = None,
    on_profile_change: any = None,
    user_storage_key: str = ""
) -> JsxElement {
    has loading: bool = false;
    has status_text: str = "Complete your profile survey to personalize the app.";
    has is_editing: bool = false;

    has username: str = "";
    has age: str = "";
    has height: str = "";
    has weight: str = "";
    has goal_weight: str = "";
    has sex: str = "MALE";
    has goal: str = "MAINTENANCE";
    has fitness_level: str = "MODERATELY_ACTIVE";
    has dietary_notes: str = "";
    has allergy_notes: str = "";
    has saved_profile: dict = {};

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

    def split_csv(text: str) -> list {
        return String(text or "").split(",").map(
            lambda item: str -> str { return item.trim(); }
        ).filter(
            lambda item: str -> bool { return item.length > 0; }
        );
    }

    def parse_num(value: str, fallback: float = -1.0) -> float {
        parsed = parseFloat(String(value or "").trim());
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
        height_num = parse_num(String(profile.height or ""), -1.0);
        weight_num = parse_num(String(profile.weight or ""), -1.0);
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

    def maybe_trigger_auth_error(text: str) -> None {
        if on_auth_error and is_auth_error_text(text) {
            on_auth_error("Session expired. Please sign in again.");
        }
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
            return {"error": error_message(response_payload, raw_text)};
        }
        return first_report_payload(response_payload);
    }

    def profile_cache_key() -> str {
        key = String(user_storage_key or "").trim().toLowerCase();
        if key.length == 0 {
            key = "anonymous";
        }
        return ["caloreceipt", key, "profile"].join(":");
    }

    def save_profile_cache(payload: dict) -> None {
        try {
            localStorage.setItem(profile_cache_key(), JSON.stringify(payload));
        } except Exception as _e {
            0;
        }
    }

    def load_profile_cache() -> dict {
        try {
            raw = localStorage.getItem(profile_cache_key());
            if raw and raw.length > 0 {
                return JSON.parse(raw);
            }
        } except Exception as _e {
            0;
        }
        return {};
    }

    def clear_profile_cache() -> None {
        try {
            localStorage.removeItem(profile_cache_key());
        } except Exception as _e {
            0;
        }
    }

    def build_profile_payload() -> dict {
        age_num = parseInt(String(age or "").trim());
        height_num = parse_num(height, -1.0);
        weight_num = parse_num(weight, -1.0);
        goal_weight_num = parse_num(goal_weight, 0.0);

        if isNaN(age_num) or age_num <= 0 or height_num <= 0 or weight_num <= 0 {
            return {};
        }
        if goal_weight_num < 0 {
            goal_weight_num = 0.0;
        }

        return {
            "username": String(username or "").trim(),
            "age": age_num,
            "sex": sex,
            "height": height_num,
            "weight": weight_num,
            "goal_weight": goal_weight_num,
            "dietary_restrictions": split_csv(dietary_notes),
            "allergies": split_csv(allergy_notes),
            "fitness_level": fitness_level,
            "goal": goal
        };
    }

    def apply_profile_to_form(profile: dict) -> None {
        saved_profile = profile;
        username = String(profile.username or "");
        age = String(profile.age or "");
        height = String(profile.height or "");
        weight = String(profile.weight or "");
        goal_weight_val = parseFloat(String(profile.goal_weight or 0));
        if isNaN(goal_weight_val) or goal_weight_val <= 0 {
            goal_weight = "";
        } else {
            goal_weight = String(profile.goal_weight);
        }
        sex = String(profile.sex or "MALE").toUpperCase();
        goal = String(profile.goal or "MAINTENANCE").toUpperCase();
        fitness_level = String(profile.fitness_level or "MODERATELY_ACTIVE").toUpperCase();
        dietary_notes = (profile.dietary_restrictions or []).join(", ");
        allergy_notes = (profile.allergies or []).join(", ");
    }

    def reset_form() -> None {
        username = "";
        age = "";
        height = "";
        weight = "";
        goal_weight = "";
        sex = "MALE";
        goal = "MAINTENANCE";
        fitness_level = "MODERATELY_ACTIVE";
        dietary_notes = "";
        allergy_notes = "";
    }

    def titleize(raw: any) -> str {
        text = String(raw or "").trim().toLowerCase();
        if text.length == 0 {
            return "-";
        }
        return text.split("_").map(
            lambda part: str -> str {
                if part.length == 0 {
                    return "";
                }
                return part.charAt(0).toUpperCase() + part.slice(1);
            }
        ).join(" ");
    }

    def display_list(raw: any) -> str {
        if is_listish(raw) and raw.length > 0 {
            return raw.join(", ");
        }
        return "None listed";
    }

    def display_goal_weight(raw: any) -> str {
        val = parseFloat(String(raw or 0));
        if isNaN(val) or val <= 0 {
            return "Not set";
        }
        return String(raw) + " lb";
    }

    async def save_profile_api() -> None {
        payload = build_profile_payload();
        if Object.keys(payload).length == 0 {
            status_text = "Enter valid age, height, and current weight before saving.";
            return;
        }

        loading = true;
        status_text = "Saving profile...";
        try {
            out = await post_authenticated_walker("SaveUserProfile", {"profile": payload});
            if out.saved {
                save_profile_cache(payload);
                apply_profile_to_form(payload);
                is_editing = false;
                status_text = "Profile saved.";
                if on_profile_change {
                    on_profile_change(payload);
                }
            } else {
                save_profile_cache(payload);
                apply_profile_to_form(payload);
                is_editing = false;
                err_text = String(out.error or JSON.stringify(out, None, 2));
                status_text = "Profile saved locally. Backend sync failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                if on_profile_change {
                    on_profile_change(payload);
                }
            }
        } except Exception as e {
            save_profile_cache(payload);
            apply_profile_to_form(payload);
            is_editing = false;
            err_text = e.toString();
            status_text = "Profile saved locally. Backend sync failed: " + err_text;
            maybe_trigger_auth_error(err_text);
            if on_profile_change {
                on_profile_change(payload);
            }
        }
        loading = false;
    }

    async def load_profile_api() -> None {
        loading = true;
        status_text = "Loading profile...";
        try {
            out = await post_authenticated_walker("GetUserProfile");
            if out and out.error {
                err_text = String(out.error);
                status_text = "Load failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }
            if not profile_has_any_data(out) {
                cached = load_profile_cache();
                if profile_has_any_data(cached) {
                    out = cached;
                    if profile_has_key_info(cached) {
                        status_text = "Profile loaded from local cache.";
                    } else {
                        status_text = "Profile is missing required fields. Complete the survey below.";
                    }
                } else {
                    saved_profile = {};
                    reset_form();
                    is_editing = true;
                    status_text = "No saved profile found. Start the survey below.";
                    loading = false;
                    return;
                }
            } else {
                if profile_has_key_info(out) {
                    status_text = "Profile loaded from backend.";
                } else {
                    status_text = "Profile is missing required fields. Complete the survey below.";
                }
            }

            save_profile_cache(out);
            apply_profile_to_form(out);
            is_editing = not profile_has_key_info(out);
            if on_profile_change {
                on_profile_change(out);
            }
        } except Exception as e {
            cached = load_profile_cache();
            if profile_has_any_data(cached) {
                apply_profile_to_form(cached);
                is_editing = not profile_has_key_info(cached);
                if profile_has_key_info(cached) {
                    status_text = "Profile loaded from local cache.";
                } else {
                    status_text = "Profile is missing required fields. Complete the survey below.";
                }
                if on_profile_change {
                    on_profile_change(cached);
                }
                loading = false;
                return;
            }
            saved_profile = {};
            reset_form();
            is_editing = true;
            err_text = e.toString();
            status_text = "Load failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    def start_editing() -> None {
        if profile_has_any_data(saved_profile) {
            apply_profile_to_form(saved_profile);
        }
        is_editing = true;
        status_text = "Edit your saved profile and save when ready.";
    }

    def cancel_edit() -> None {
        if profile_has_key_info(saved_profile) {
            apply_profile_to_form(saved_profile);
            is_editing = false;
            status_text = "Viewing saved profile.";
            return;
        }
        if profile_has_any_data(saved_profile) {
            apply_profile_to_form(saved_profile);
            is_editing = true;
            status_text = "Profile is missing required fields. Complete the survey below.";
            return;
        }
        reset_form();
        status_text = "No saved profile yet. Complete the survey to continue.";
    }

    async def clear_profile_api() -> None {
        loading = true;
        status_text = "Clearing profile...";
        try {
            root spawn ClearUserProfile();
            saved_profile = {};
            reset_form();
            clear_profile_cache();
            is_editing = true;
            status_text = "Profile cleared.";
            if on_profile_change {
                on_profile_change({});
            }
        } except Exception as e {
            err_text = e.toString();
            status_text = "Clear failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async can with entry {
        await load_profile_api();
    }

    return
        <div
            style={{
                "background": "#ffffffde",
                "border": "1px solid #d2e3f5",
                "borderRadius": "18px",
                "padding": "18px",
                "display": "grid",
                "gap": "14px"
            }}
        >
            <div style={{"display": "flex", "justifyContent": "space-between", "gap": "10px", "alignItems": "center", "flexWrap": "wrap"}}>
                <div>
                    <h2 style={{"margin": "0"}}>User Profile</h2>
                    <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                        Save your onboarding answers once, then edit only when something changes.
                    </p>
                </div>
                <div style={{"padding": "8px 12px", "border": ("1px solid #fbbf24" if is_editing else "1px solid #86efac"), "background": ("#fffbeb" if is_editing else "#f0fdf4"), "borderRadius": "999px", "fontWeight": "700"}}>
                    {("Survey Mode" if is_editing else "Profile Locked")}
                </div>
            </div>

            <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            {(
                <div style={{"display": "grid", "gap": "12px"}}>
                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={start_editing} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#dbeafe", "fontWeight": "700"}}>Edit Profile</button>
                        <button onClick={load_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff"}}>Refresh</button>
                        <button onClick={clear_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #991b1b", "background": "#fee2e2"}}>Clear Profile</button>
                    </div>

                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(230px, 1fr))", "gap": "12px"}}>
                        <div style={{"border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "8px"}}>
                            <h3 style={{"margin": "0"}}>Core Stats</h3>
                            <div><b>Name:</b> {(saved_profile.username if String(saved_profile.username or "").trim().length > 0 else "Not set")}</div>
                            <div><b>Age:</b> {saved_profile.age}</div>
                            <div><b>Sex:</b> {titleize(saved_profile.sex)}</div>
                            <div><b>Height:</b> {String(saved_profile.height) + " in"}</div>
                            <div><b>Current Weight:</b> {String(saved_profile.weight) + " lb"}</div>
                            <div><b>Goal Weight:</b> {display_goal_weight(saved_profile.goal_weight)}</div>
                        </div>

                        <div style={{"border": "1px solid #dcfce7", "background": "#f0fdf4", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "8px"}}>
                            <h3 style={{"margin": "0"}}>Training Goals</h3>
                            <div><b>Overall Goal:</b> {titleize(saved_profile.goal)}</div>
                            <div><b>Fitness Level:</b> {titleize(saved_profile.fitness_level)}</div>
                            <div style={{"opacity": "0.74"}}>Update these if your training block or target weight changes.</div>
                        </div>

                        <div style={{"border": "1px solid #fde68a", "background": "#fffbeb", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "8px"}}>
                            <h3 style={{"margin": "0"}}>Food Preferences</h3>
                            <div><b>Dietary Restrictions:</b> {display_list(saved_profile.dietary_restrictions)}</div>
                            <div><b>Allergies:</b> {display_list(saved_profile.allergies)}</div>
                        </div>
                    </div>
                </div>
            ) if (profile_has_key_info(saved_profile) and not is_editing) else (
                <div style={{"display": "grid", "gap": "12px"}}>
                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(240px, 1fr))", "gap": "12px"}}>
                        <div style={{"border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>About You</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>Start with the core details used throughout the app.</div>
                            </div>
                            <div style={{"display": "grid", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Name</label>
                                    <input value={username} onChange={lambda e: any -> None { username = e.target.value; }} placeholder="Preferred name" style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}} />
                                </div>
                                <div style={{"display": "grid", "gridTemplateColumns": "repeat(2, minmax(0, 1fr))", "gap": "10px"}}>
                                    <div>
                                        <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Age</label>
                                        <input value={age} onChange={lambda e: any -> None { age = e.target.value; }} placeholder="Years" style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}} />
                                    </div>
                                    <div>
                                        <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Sex</label>
                                        <select value={sex} onChange={lambda e: any -> None { sex = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #bfdbfe", "borderRadius": "10px"}}>
                                            <option value="MALE">Male</option>
                                            <option value="FEMALE">Female</option>
                                            <option value="OTHER">Other</option>
                                            <option value="PREFER_NOT_TO_SAY">Prefer not to say</option>
                                        </select>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div style={{"border": "1px solid #dcfce7", "background": "#f0fdf4", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>Body Metrics</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>Use current measurements and add a goal weight if you have one.</div>
                            </div>
                            <div style={{"display": "grid", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Height (in)</label>
                                    <input value={height} onChange={lambda e: any -> None { height = e.target.value; }} placeholder="70" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Current Weight (lb)</label>
                                    <input value={weight} onChange={lambda e: any -> None { weight = e.target.value; }} placeholder="170" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Goal Weight (lb)</label>
                                    <input value={goal_weight} onChange={lambda e: any -> None { goal_weight = e.target.value; }} placeholder="Optional" style={{"width": "100%", "padding": "10px", "border": "1px solid #86efac", "borderRadius": "10px"}} />
                                </div>
                            </div>
                        </div>

                        <div style={{"border": "1px solid #fde68a", "background": "#fffbeb", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                            <div>
                                <div style={{"fontWeight": "800"}}>Goals And Food Preferences</div>
                                <div style={{"opacity": "0.76", "fontSize": "0.92rem"}}>Capture activity level, overall goals, allergies, and restrictions.</div>
                            </div>
                            <div style={{"display": "grid", "gap": "10px"}}>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Fitness Level</label>
                                    <select value={fitness_level} onChange={lambda e: any -> None { fitness_level = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}}>
                                        <option value="SEDENTARY">Sedentary</option>
                                        <option value="LIGHTLY_ACTIVE">Lightly active</option>
                                        <option value="MODERATELY_ACTIVE">Moderately active</option>
                                        <option value="VERY_ACTIVE">Very active</option>
                                        <option value="ATHLETE">Athlete</option>
                                    </select>
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Overall Goal</label>
                                    <select value={goal} onChange={lambda e: any -> None { goal = e.target.value; }} style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}}>
                                        <option value="FAT_LOSS">Fat loss</option>
                                        <option value="MAINTENANCE">Maintenance</option>
                                        <option value="LEAN_BULK">Lean bulk</option>
                                        <option value="MUSCLE_GAIN">Muscle gain</option>
                                        <option value="ENDURANCE_PERFORMANCE">Endurance performance</option>
                                    </select>
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Dietary Restrictions</label>
                                    <input value={dietary_notes} onChange={lambda e: any -> None { dietary_notes = e.target.value; }} placeholder="Comma-separated, e.g. vegetarian, halal" style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}} />
                                </div>
                                <div>
                                    <label style={{"display": "block", "fontWeight": "700", "marginBottom": "4px"}}>Allergies</label>
                                    <input value={allergy_notes} onChange={lambda e: any -> None { allergy_notes = e.target.value; }} placeholder="Comma-separated, e.g. peanuts, shellfish" style={{"width": "100%", "padding": "10px", "border": "1px solid #fcd34d", "borderRadius": "10px"}} />
                                </div>
                            </div>
                        </div>
                    </div>

                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={save_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "700"}}>Save Profile</button>
                        <button onClick={cancel_edit} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff"}}>Cancel</button>
                        <button onClick={load_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#eff6ff"}}>Reload</button>
                        <button onClick={clear_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #991b1b", "background": "#fee2e2"}}>Clear Profile</button>
                    </div>
                </div>
            )}
        </div>;
}
