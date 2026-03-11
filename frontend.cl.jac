import from tab_receipt_upload { ReceiptUploadTab }
import from tab_dashboard_ai { DashboardAiTab }
import from tab_user_profile { UserProfileTab }
import from tab_recipes { RecipesTab }
import from tab_nutrition { NutritionTab }

def:pub app() -> JsxElement {
    has active_tab: str = "receipt";
    has app_state: dict = {"pantry_items": []};
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

    def run_periodic_pantry_merge() -> None {
        current_items: list = [];
        if app_state and app_state.pantry_items {
            current_items = app_state.pantry_items;
        }
        merged_items = merge_identical_pantry_items(current_items);
        if JSON.stringify(merged_items) != JSON.stringify(current_items) {
            app_state = {"pantry_items": merged_items};
        }
    }

    can with entry {
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
    }

    can with exit {
        if pantry_merge_timer_id >= 0 {
            window.clearInterval(pantry_merge_timer_id);
            pantry_merge_timer_id = -1;
        }
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
                    <ReceiptUploadTab shared_state={app_state} />
                </div>
                <div style={{"display": ("block" if active_tab == "dashboard" else "none")}}>
                    <DashboardAiTab />
                </div>
                <div style={{"display": ("block" if active_tab == "profile" else "none")}}>
                    <UserProfileTab />
                </div>
                <div style={{"display": ("block" if active_tab == "recipes" else "none")}}>
                    <RecipesTab shared_state={app_state} />
                </div>
                <div style={{"display": ("block" if active_tab == "nutrition" else "none")}}>
                    <NutritionTab />
                </div>
            </div>
        </div>;
}
