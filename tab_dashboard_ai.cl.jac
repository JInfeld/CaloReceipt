sv import from user {
    GenerateUserMacroNeeds,
    GetUserProfile
}

def:pub DashboardAiTab() -> JsxElement {
    has loading: bool = false;
    has status_text: str = "Macro API ready.";
    has macro_needs: dict = {};

    has macro_cards: list = [
        {"name": "Protein", "consumed": 138, "target": 180, "color": "#0ea5e9"},
        {"name": "Carbs", "consumed": 188, "target": 240, "color": "#f97316"},
        {"name": "Fat", "consumed": 58, "target": 75, "color": "#8b5cf6"}
    ];
    has hydration_liters: str = "2.1";
    has sleep_hours: str = "7.4";

    has chat_input: str = "";
    has chat_history: list = [
        {"role": "bot", "text": "Tell me your cooking plan and I will draft a grocery list."}
    ];
    has grocery_list: list = [
        "Chicken breast (2 lb)",
        "Greek yogurt (32 oz)",
        "Frozen berries (1 bag)"
    ];

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

    def macro_percent(consumed: int, target: int) -> int {
        if target <= 0 {
            return 0;
        }
        value = parseInt(((consumed * 100) / target).toString());
        if value < 0 {
            return 0;
        }
        if value > 100 {
            return 100;
        }
        return value;
    }

    def quick_bot_reply(prompt: str) -> str {
        lower = prompt.toLowerCase();
        if lower.includes("protein") {
            return "To increase protein, prioritize chicken, fish, greek yogurt, eggs, and lentils in your next list.";
        }
        if lower.includes("budget") {
            return "Budget mode: buy frozen vegetables, oats, dry beans, and bulk rice first.";
        }
        if lower.includes("quick") or lower.includes("fast") {
            return "For quicker meals, I recommend pre-cut produce, rotisserie chicken, and microwave grains.";
        }
        return "I can tune your grocery list by goals, budget, allergies, and prep time. Ask me for one of those.";
    }

    def send_chat_message() -> None {
        clean = chat_input.trim();
        if not clean {
            return;
        }
        chat_history = chat_history.concat([{"role": "user", "text": clean}]);
        bot_text = quick_bot_reply(clean);
        chat_history = chat_history.concat([{"role": "bot", "text": bot_text}]);
        chat_input = "";
    }

    def macro_is_short(index: int) -> bool {
        consumed = parseInt(String(macro_cards[index].consumed));
        target = parseInt(String(macro_cards[index].target));
        if isNaN(consumed) or isNaN(target) {
            return false;
        }
        return consumed < target;
    }

    def generate_grocery_draft() -> None {
        next_list: list = [];
        if macro_is_short(0) {
            next_list = next_list.concat(["Lean turkey", "Cottage cheese", "Tofu"]);
        }
        if macro_is_short(1) {
            next_list = next_list.concat(["Brown rice", "Bananas", "Whole-grain wraps"]);
        }
        if macro_is_short(2) {
            next_list = next_list.concat(["Avocados", "Olive oil", "Mixed nuts"]);
        }
        if next_list.length == 0 {
            next_list = ["Macros on track: maintain your current shopping list."];
        }

        grocery_list = next_list;
        chat_history = chat_history.concat([{
            "role": "bot",
            "text": "Drafted a new grocery list based on current macro gaps. Review it in the panel on the right."
        }]);
    }

    def apply_macro_targets(protein_target: int, carbs_target: int, fat_target: int) -> None {
        macro_cards = [
            {
                "name": "Protein",
                "consumed": macro_cards[0].consumed,
                "target": protein_target,
                "color": "#0ea5e9"
            },
            {
                "name": "Carbs",
                "consumed": macro_cards[1].consumed,
                "target": carbs_target,
                "color": "#f97316"
            },
            {
                "name": "Fat",
                "consumed": macro_cards[2].consumed,
                "target": fat_target,
                "color": "#8b5cf6"
            }
        ];
    }

    async def generate_macro_needs_api() -> None {
        loading = true;
        status_text = "Generating macro needs from backend profile...";
        try {
            profile_result = root spawn GetUserProfile();
            profile_out = first_report_payload(profile_result);
            if not profile_out or Object.keys(profile_out).length == 0 {
                status_text = "No saved user profile found. Save one in User Profile tab first.";
                loading = false;
                return;
            }

            result = root spawn GenerateUserMacroNeeds();
            out = first_report_payload(result);
            if out.ok {
                macro_needs = out;
                apply_macro_targets(
                    parseInt(parseFloat(String(out.protein_g)).toString()),
                    parseInt(parseFloat(String(out.carbs_g)).toString()),
                    parseInt(parseFloat(String(out.fat_g)).toString())
                );
                status_text = "Macro needs generated from API and applied to dashboard targets.";
                chat_history = chat_history.concat([{
                    "role": "bot",
                    "text": "Fresh macro targets loaded. You can now generate a grocery list from the updated gaps."
                }]);
            } else {
                status_text = "Macro generation failed: " + String(out.error or "unknown error");
            }
        } except Exception as e {
            status_text = "Macro generation failed: " + e.toString();
        }
        loading = false;
    }

    return
        <div
            style={{
                "background": "#ffffffde",
                "border": "1px solid #d2e3f5",
                "borderRadius": "18px",
                "padding": "18px",
                "display": "grid",
                "gap": "16px"
            }}
        >
            <div>
                <h2 style={{"margin": "0"}}>Dashboard / AI Bot</h2>
                <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                    Macro status plus a chat-style grocery planning assistant.
                </p>
            </div>

            <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                <button onClick={generate_macro_needs_api} style={{"padding": "8px 12px", "border": "1px solid #1d4ed8", "borderRadius": "10px", "background": "#dbeafe", "fontWeight": "700"}}>
                    Generate Macro Needs (API)
                </button>
                <button onClick={generate_grocery_draft} style={{"padding": "8px 12px", "border": "1px solid #0f766e", "borderRadius": "10px", "background": "#ccfbf1", "fontWeight": "700"}}>
                    Generate Grocery List (Macro Gaps)
                </button>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(200px, 1fr))", "gap": "12px"}}>
                {macro_cards.map(
                    lambda macro: dict -> JsxElement { return
                        <div key={macro.name} style={{"border": "1px solid #dbeafe", "borderRadius": "12px", "padding": "12px", "background": "#f8fbff"}}>
                            <div style={{"display": "flex", "justifyContent": "space-between", "fontWeight": "700"}}>
                                <span>{macro.name}</span>
                                <span>{String(macro_percent(macro.consumed, macro.target))}%</span>
                            </div>
                            <div style={{"marginTop": "8px", "height": "10px", "borderRadius": "999px", "background": "#e2e8f0", "overflow": "hidden"}}>
                                <div
                                    style={{
                                        "height": "100%",
                                        "width": [String(macro_percent(macro.consumed, macro.target)), "%"].join(""),
                                        "background": macro.color,
                                        "borderRadius": "999px"
                                    }}
                                />
                            </div>
                            <div style={{"marginTop": "8px", "fontSize": "0.92rem"}}>
                                {[String(macro.consumed), " / ", String(macro.target), " g"].join("")}
                            </div>
                        </div>; }
                )}
                <div style={{"border": "1px solid #dcfce7", "borderRadius": "12px", "padding": "12px", "background": "#f0fdf4"}}>
                    <div style={{"fontWeight": "700"}}>Hydration</div>
                    <div style={{"fontSize": "1.3rem", "marginTop": "6px"}}>{hydration_liters} L</div>
                    <div style={{"fontSize": "0.88rem", "opacity": "0.72"}}>Daily water intake</div>
                </div>
                <div style={{"border": "1px solid #fde68a", "borderRadius": "12px", "padding": "12px", "background": "#fffbeb"}}>
                    <div style={{"fontWeight": "700"}}>Sleep</div>
                    <div style={{"fontSize": "1.3rem", "marginTop": "6px"}}>{sleep_hours} hrs</div>
                    <div style={{"fontSize": "0.88rem", "opacity": "0.72"}}>Last night</div>
                </div>
            </div>

            <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#f8fafc"}}>
                <h3 style={{"margin": "0 0 8px 0"}}>Latest Macro API Output</h3>
                <pre style={{"margin": "0", "background": "#0f172a", "color": "#e2e8f0", "borderRadius": "10px", "padding": "10px", "overflowX": "auto"}}>{JSON.stringify(macro_needs, None, 2)}</pre>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "minmax(0, 2fr) minmax(260px, 1fr)", "gap": "12px"}}>
                <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "display": "grid", "gap": "10px", "background": "#fcfdff"}}>
                    <h3 style={{"margin": "0"}}>AI Grocery Chat</h3>
                    <div style={{"maxHeight": "270px", "overflowY": "auto", "display": "grid", "gap": "8px"}}>
                        {chat_history.map(
                            lambda msg: dict -> JsxElement { return
                                <div key={[msg.role, msg.text].join("-")} style={{"justifySelf": ("end" if msg.role == "user" else "start"), "background": ("#dbeafe" if msg.role == "user" else "#eef2ff"), "border": "1px solid #c7d2fe", "borderRadius": "10px", "padding": "8px 10px", "maxWidth": "80%"}}>
                                    <div style={{"fontSize": "0.75rem", "opacity": "0.68", "fontWeight": "700"}}>{msg.role.toUpperCase()}</div>
                                    <div>{msg.text}</div>
                                </div>; }
                        )}
                    </div>
                    <div style={{"display": "flex", "gap": "8px"}}>
                        <input value={chat_input} onChange={lambda e: any -> None { chat_input = e.target.value; }} placeholder="Ask for grocery feedback..." style={{"flex": "1", "padding": "9px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1"}} />
                        <button onClick={send_chat_message} style={{"padding": "9px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#dbeafe", "fontWeight": "700"}}>Send</button>
                    </div>
                </div>

                <div style={{"border": "1px solid #d1fae5", "borderRadius": "12px", "padding": "12px", "background": "#f0fdfa", "display": "grid", "gap": "10px", "height": "fit-content"}}>
                    <h3 style={{"margin": "0"}}>Generated Grocery List</h3>
                    <ul style={{"margin": "0", "paddingLeft": "18px", "display": "grid", "gap": "6px"}}>
                        {grocery_list.map(
                            lambda item: str -> JsxElement { return <li key={item}>{item}</li>; }
                        )}
                    </ul>
                </div>
            </div>
        </div>;
}
