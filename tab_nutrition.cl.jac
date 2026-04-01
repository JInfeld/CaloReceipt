def:pub NutritionTab(
    shared_state: dict = {},
    on_nutrition_change: any = None,
    is_hydrating: bool = false
) -> JsxElement {
    has selected_day_index: int = 0;
    has weekly_history: list = [
        {"day": "Mon", "protein": 82, "carbs": 71, "fat": 66, "move": 74},
        {"day": "Tue", "protein": 88, "carbs": 79, "fat": 70, "move": 81},
        {"day": "Wed", "protein": 92, "carbs": 76, "fat": 68, "move": 79},
        {"day": "Thu", "protein": 73, "carbs": 64, "fat": 58, "move": 62},
        {"day": "Fri", "protein": 96, "carbs": 88, "fat": 77, "move": 91},
        {"day": "Sat", "protein": 84, "carbs": 72, "fat": 71, "move": 86},
        {"day": "Sun", "protein": 90, "carbs": 75, "fat": 73, "move": 84}
    ];

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

    def push_nutrition_state() -> None {
        shared_state.nutrition_history = weekly_history;
        shared_state.nutrition_selected_day_index = selected_day_index;
        if on_nutrition_change and not is_hydrating {
            on_nutrition_change({
                "weekly_history": weekly_history,
                "selected_day_index": selected_day_index
            });
        }
    }

    can with entry {
        if shared_state.nutrition_history and is_listish(shared_state.nutrition_history) and shared_state.nutrition_history.length > 0 {
            weekly_history = shared_state.nutrition_history;
        }
        if shared_state.nutrition_selected_day_index != None {
            idx = parseInt(String(shared_state.nutrition_selected_day_index));
            if not isNaN(idx) and idx >= 0 and idx < weekly_history.length {
                selected_day_index = idx;
            }
        }
        push_nutrition_state();
    }

    def selected_day() -> dict {
        return weekly_history[selected_day_index];
    }

    def ring_background(percent: int, color: str) -> str {
        safe = percent;
        if safe < 0 {
            safe = 0;
        }
        if safe > 100 {
            safe = 100;
        }
        return [
            "conic-gradient(",
            color,
            " ",
            String(safe),
            "%, #e2e8f0 ",
            String(safe),
            "% 100%)"
        ].join("");
    }

    def to_percent_int(raw: any) -> int {
        parsed = parseInt(String(raw));
        if isNaN(parsed) {
            return 0;
        }
        if parsed < 0 {
            return 0;
        }
        if parsed > 100 {
            return 100;
        }
        return parsed;
    }

    def ring(label: str, percent: int, color: str) -> JsxElement {
        return
            <div style={{"display": "grid", "justifyItems": "center", "gap": "8px"}}>
                <div
                    style={{
                        "width": "120px",
                        "height": "120px",
                        "borderRadius": "50%",
                        "background": ring_background(percent, color),
                        "display": "grid",
                        "placeItems": "center"
                    }}
                >
                    <div
                        style={{
                            "width": "78px",
                            "height": "78px",
                            "borderRadius": "50%",
                            "background": "#ffffff",
                            "display": "grid",
                            "placeItems": "center",
                            "fontWeight": "700"
                        }}
                    >
                        {String(percent)}%
                    </div>
                </div>
                <div style={{"fontWeight": "700"}}>{label}</div>
            </div>;
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
            <div>
                <h2 style={{"margin": "0"}}>Nutrition History</h2>
                <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                    Day-by-day macro completion with ring visuals inspired by activity tracking apps.
                </p>
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                {weekly_history.map(
                    lambda day_item: dict -> JsxElement { return
                        <button
                            key={day_item.day}
                            onClick={lambda -> None {
                                next_idx = weekly_history.findIndex(
                                    lambda x: dict -> bool { return x.day == day_item.day; }
                                );
                                if next_idx >= 0 {
                                    selected_day_index = next_idx;
                                    push_nutrition_state();
                                }
                            }}
                            style={{
                                "padding": "8px 10px",
                                "borderRadius": "999px",
                                "border": "1px solid #cbd5e1",
                                "background": ("#dbeafe" if selected_day().day == day_item.day else "#ffffff"),
                                "fontWeight": "700"
                            }}
                        >
                            {day_item.day}
                        </button>; }
                )}
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(180px, 1fr))", "gap": "12px", "justifyItems": "center"}}>
                {ring("Protein", to_percent_int(selected_day().protein), "#0ea5e9")}
                {ring("Carbs", to_percent_int(selected_day().carbs), "#f97316")}
                {ring("Fat", to_percent_int(selected_day().fat), "#8b5cf6")}
                {ring("Move", to_percent_int(selected_day().move), "#10b981")}
            </div>

            <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#f8fafc", "display": "grid", "gap": "8px"}}>
                <h3 style={{"margin": "0"}}>Weekly Trend</h3>
                {weekly_history.map(
                    lambda day_item: dict -> JsxElement {
                        day_protein = to_percent_int(day_item.protein);
                        day_carbs = to_percent_int(day_item.carbs);
                        day_fat = to_percent_int(day_item.fat);
                        day_move = to_percent_int(day_item.move);
                        day_avg = parseInt(((day_protein + day_carbs + day_fat + day_move) / 4).toString());
                        return
                        <div key={["trend", day_item.day].join("-")} style={{"display": "grid", "gap": "4px"}}>
                            <div style={{"display": "flex", "justifyContent": "space-between", "fontSize": "0.9rem"}}>
                                <span>{day_item.day}</span>
                                <span>{String(day_avg)}% avg</span>
                            </div>
                            <div style={{"height": "10px", "borderRadius": "999px", "background": "#e2e8f0", "overflow": "hidden"}}>
                                <div
                                    style={{
                                        "height": "100%",
                                        "width": [String(day_avg), "%"].join(""),
                                        "background": "linear-gradient(90deg, #0ea5e9 0%, #10b981 100%)"
                                    }}
                                />
                            </div>
                        </div>;
                    }
                )}
            </div>
        </div>;
}
