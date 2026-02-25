import from tab_receipt_upload { ReceiptUploadTab }
import from tab_dashboard_ai { DashboardAiTab }
import from tab_user_profile { UserProfileTab }
import from tab_recipes { RecipesTab }
import from tab_nutrition { NutritionTab }

def:pub app() -> JsxElement {
    has active_tab: str = "receipt";

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

    def active_tab_view() -> JsxElement {
        if active_tab == "receipt" {
            return <ReceiptUploadTab />;
        } elif active_tab == "dashboard" {
            return <DashboardAiTab />;
        } elif active_tab == "profile" {
            return <UserProfileTab />;
        } elif active_tab == "recipes" {
            return <RecipesTab />;
        } elif active_tab == "nutrition" {
            return <NutritionTab />;
        }
        return <ReceiptUploadTab />;
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

                {active_tab_view()}
            </div>
        </div>;
}
