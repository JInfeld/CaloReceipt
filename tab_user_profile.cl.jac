sv import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile
}

def:pub UserProfileTab() -> JsxElement {
    has survey_step: int = 0;
    has loading: bool = false;
    has status_text: str = "Profile not saved yet.";

    has user_id: str = "";
    has username: str = "";
    has pax: str = "1";
    has age: str = "";
    has height: str = "";
    has weight: str = "";

    has sex: str = "MALE";
    has goal: str = "MUSCLE_GAIN";
    has fitness_level: str = "MODERATELY_ACTIVE";
    has fitness_link: str = "Apple Health";
    has dietary_notes: str = "";
    has allergy_notes: str = "";
    has saved_profile: dict = {};

    def ensure_user_id() -> None {
        if user_id.trim() {
            return;
        }
        now_obj = Reflect.construct(Date, []);
        epoch_text = now_obj.getTime().toString();
        rand_text = Math.floor(Math.random() * 1000).toString();
        user_id = [epoch_text, rand_text].join("");
    }

    def split_csv(text: str) -> list {
        if not text.trim() {
            return [];
        }
        return text.split(",").map(
            lambda item: str -> str { return item.trim(); }
        ).filter(
            lambda item: str -> bool { return item.length > 0; }
        );
    }

    def parse_num(value: str, fallback: float = -1.0) -> float {
        parsed = parseFloat(value);
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def build_profile_payload() -> dict {
        ensure_user_id();

        age_num = parseInt(age.trim());
        height_num = parse_num(height, -1.0);
        weight_num = parse_num(weight, -1.0);

        if isNaN(age_num) or height_num <= 0 or weight_num <= 0 {
            return {};
        }

        return {
            "user_id": parseInt(user_id),
            "age": age_num,
            "sex": sex,
            "height": height_num,
            "weight": weight_num,
            "dietary_restrictions": split_csv(dietary_notes),
            "allergies": split_csv(allergy_notes),
            "fitness_level": fitness_level,
            "goal": goal
        };
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

    def step_title() -> str {
        if survey_step == 0 {
            return "Basic Info";
        } elif survey_step == 1 {
            return "Health Goals";
        }
        return "Review";
    }

    def next_step() -> None {
        if survey_step < 2 {
            survey_step += 1;
        }
    }

    def prev_step() -> None {
        if survey_step > 0 {
            survey_step -= 1;
        }
    }

    async def save_profile_api() -> None {
        payload = build_profile_payload();
        if Object.keys(payload).length == 0 {
            status_text = "Enter valid age, height, and weight before saving.";
            return;
        }

        loading = true;
        status_text = "Saving profile...";
        try {
            result = root spawn SaveUserProfile(profile=payload);
            out = first_report_payload(result);
            if out.saved {
                saved_profile = payload;
                status_text = "Profile saved to backend.";
            } else {
                status_text = "Save failed: " + String(out.error or JSON.stringify(out, None, 2));
            }
        } except Exception as e {
            status_text = "Save failed: " + e.toString();
        }
        loading = false;
    }

    async def load_profile_api() -> None {
        loading = true;
        status_text = "Loading profile...";
        try {
            result = root spawn GetUserProfile();
            out = first_report_payload(result);
            if not out or Object.keys(out).length == 0 {
                status_text = "No saved profile found.";
                saved_profile = {};
                loading = false;
                return;
            }

            saved_profile = out;
            ensure_user_id();
            user_id = String(out.user_id);
            age = String(out.age);
            height = String(out.height);
            weight = String(out.weight);
            sex = String(out.sex).toUpperCase();
            goal = String(out.goal).toUpperCase();
            fitness_level = String(out.fitness_level).toUpperCase();
            dietary_notes = (out.dietary_restrictions or []).join(", ");
            allergy_notes = (out.allergies or []).join(", ");
            status_text = "Profile loaded from backend.";
        } except Exception as e {
            status_text = "Load failed: " + e.toString();
        }
        loading = false;
    }

    async def clear_profile_api() -> None {
        loading = true;
        status_text = "Clearing profile...";
        try {
            root spawn ClearUserProfile();
            saved_profile = {};
            age = "";
            height = "";
            weight = "";
            dietary_notes = "";
            allergy_notes = "";
            status_text = "Profile cleared from backend.";
        } except Exception as e {
            status_text = "Clear failed: " + e.toString();
        }
        loading = false;
    }

    can with entry {
        ensure_user_id();
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
                    <h2 style={{"margin": "0"}}>User Profile Survey</h2>
                    <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                        This tab now saves/loads profile data through walkers.
                    </p>
                </div>
                <div style={{"padding": "8px 12px", "border": "1px solid #c4b5fd", "background": "#ede9fe", "borderRadius": "999px", "fontWeight": "700"}}>
                    Step {String(survey_step + 1)} / 3
                </div>
            </div>

            <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(3, minmax(0, 1fr))", "gap": "8px"}}>
                <button onClick={lambda -> None { survey_step = 0; }} style={{"padding": "8px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if survey_step >= 0 else "#ffffff")}}>Basic</button>
                <button onClick={lambda -> None { survey_step = 1; }} style={{"padding": "8px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if survey_step >= 1 else "#ffffff")}}>Goals</button>
                <button onClick={lambda -> None { survey_step = 2; }} style={{"padding": "8px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if survey_step >= 2 else "#ffffff")}}>Review</button>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "minmax(0, 2fr) minmax(240px, 1fr)", "gap": "12px"}}>
                <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#f8fbff", "display": "grid", "gap": "10px"}}>
                    <h3 style={{"margin": "0"}}>{step_title()}</h3>

                    {(
                        <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(180px, 1fr))", "gap": "10px"}}>
                            <div><label>User ID</label><input value={user_id} onChange={lambda e: any -> None { user_id = e.target.value; }} placeholder="auto-generated" /></div>
                            <div><label>Username</label><input value={username} onChange={lambda e: any -> None { username = e.target.value; }} placeholder="username" /></div>
                            <div><label>Household / Pax</label><input value={pax} onChange={lambda e: any -> None { pax = e.target.value; }} placeholder="1" /></div>
                            <div><label>Age</label><input value={age} onChange={lambda e: any -> None { age = e.target.value; }} placeholder="age" /></div>
                            <div><label>Height (in)</label><input value={height} onChange={lambda e: any -> None { height = e.target.value; }} placeholder="height" /></div>
                            <div><label>Weight (lb)</label><input value={weight} onChange={lambda e: any -> None { weight = e.target.value; }} placeholder="weight" /></div>
                            <div>
                                <label>Sex</label>
                                <select value={sex} onChange={lambda e: any -> None { sex = e.target.value; }}>
                                    <option value="MALE">MALE</option>
                                    <option value="FEMALE">FEMALE</option>
                                    <option value="OTHER">OTHER</option>
                                    <option value="PREFER_NOT_TO_SAY">PREFER_NOT_TO_SAY</option>
                                </select>
                            </div>
                        </div>
                    ) if survey_step == 0 else <div />}

                    {(
                        <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(180px, 1fr))", "gap": "10px"}}>
                            <div>
                                <label>Goal</label>
                                <select value={goal} onChange={lambda e: any -> None { goal = e.target.value; }}>
                                    <option value="FAT_LOSS">FAT_LOSS</option>
                                    <option value="MAINTENANCE">MAINTENANCE</option>
                                    <option value="LEAN_BULK">LEAN_BULK</option>
                                    <option value="MUSCLE_GAIN">MUSCLE_GAIN</option>
                                    <option value="ENDURANCE_PERFORMANCE">ENDURANCE_PERFORMANCE</option>
                                </select>
                            </div>
                            <div>
                                <label>Fitness Level</label>
                                <select value={fitness_level} onChange={lambda e: any -> None { fitness_level = e.target.value; }}>
                                    <option value="SEDENTARY">SEDENTARY</option>
                                    <option value="LIGHTLY_ACTIVE">LIGHTLY_ACTIVE</option>
                                    <option value="MODERATELY_ACTIVE">MODERATELY_ACTIVE</option>
                                    <option value="VERY_ACTIVE">VERY_ACTIVE</option>
                                    <option value="ATHLETE">ATHLETE</option>
                                </select>
                            </div>
                            <div>
                                <label>Fitness Data Link</label>
                                <select value={fitness_link} onChange={lambda e: any -> None { fitness_link = e.target.value; }}>
                                    <option value="Apple Health">Apple Health</option>
                                    <option value="Google Fit">Google Fit</option>
                                    <option value="Fitbit">Fitbit</option>
                                    <option value="Not Connected">Not Connected</option>
                                </select>
                            </div>
                            <div><label>Dietary Notes</label><input value={dietary_notes} onChange={lambda e: any -> None { dietary_notes = e.target.value; }} placeholder="e.g. vegetarian" /></div>
                            <div><label>Allergies</label><input value={allergy_notes} onChange={lambda e: any -> None { allergy_notes = e.target.value; }} placeholder="e.g. peanuts" /></div>
                        </div>
                    ) if survey_step == 1 else <div />}

                    {(
                        <div style={{"display": "grid", "gap": "8px"}}>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>User ID:</b> {user_id}</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Username:</b> {username if username.trim() else "-"}</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Pax:</b> {pax}</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Height / Weight:</b> {height} in / {weight} lb</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Goal:</b> {goal}</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Fitness Level:</b> {fitness_level}</div>
                            <div style={{"padding": "8px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "10px"}}><b>Fitness Link:</b> {fitness_link}</div>
                        </div>
                    ) if survey_step == 2 else <div />}

                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                        <button onClick={prev_step} disabled={survey_step == 0} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #cbd5e1"}}>Back</button>
                        <button onClick={next_step} disabled={survey_step == 2} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#dbeafe", "fontWeight": "700"}}>Next</button>
                        <button onClick={save_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "700"}}>Save Profile (API)</button>
                        <button onClick={load_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#eff6ff", "fontWeight": "700"}}>Load Profile (API)</button>
                        <button onClick={clear_profile_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #991b1b", "background": "#fee2e2", "fontWeight": "700"}}>Clear Profile (API)</button>
                    </div>
                </div>

                <div style={{"border": "1px solid #fbcfe8", "borderRadius": "12px", "padding": "12px", "background": "#fdf2f8", "height": "fit-content"}}>
                    <h3 style={{"margin": "0 0 8px 0"}}>Saved Backend Payload</h3>
                    <pre style={{"margin": "0", "background": "#0f172a", "color": "#e2e8f0", "borderRadius": "10px", "padding": "10px", "overflowX": "auto"}}>{JSON.stringify(saved_profile, None, 2)}</pre>
                </div>
            </div>
        </div>;
}
