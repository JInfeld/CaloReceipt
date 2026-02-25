sv import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ClearGeneratedRecipe
}
sv import from user {
    GetUserProfile,
    GenerateUserMacroNeeds
}

def:pub RecipesTab() -> JsxElement {
    has filter_mode: str = "all";
    has loading: bool = false;
    has status_text: str = "Recipe API ready.";

    has recipes: list = [
        {
            "id": 1,
            "title": "Lemon Garlic Chicken Bowl",
            "last_cooked": "2 days ago",
            "rating": 4,
            "favorite": true,
            "notes": "Great post-workout meal"
        },
        {
            "id": 2,
            "title": "Tofu Veggie Stir Fry",
            "last_cooked": "5 days ago",
            "rating": 3,
            "favorite": false,
            "notes": "Needed more sauce"
        }
    ];

    has pantry_items: list = [];
    has pantry_name: str = "";
    has pantry_quantity: str = "1";
    has pantry_unit: str = "PIECE";
    has pantry_cost: str = "0";
    has pantry_protein: str = "0";
    has pantry_carb: str = "0";
    has pantry_fat: str = "0";

    has generated_recipe: dict = {};
    has macro_needs: dict = {};
    has new_recipe_idea: dict = {};

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

    def to_num(value: str, fallback: float = 0.0) -> float {
        parsed = parseFloat(value);
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def visible_recipes() -> list {
        if filter_mode == "favorites" {
            return recipes.filter(
                lambda recipe: dict -> bool { return recipe.favorite; }
            );
        }
        if filter_mode == "history" {
            return recipes;
        }
        return recipes;
    }

    def toggle_favorite(recipe_id: int) -> None {
        next_recipes: list = [];
        for recipe in recipes {
            if recipe.id == recipe_id {
                next_recipes = next_recipes.concat([{
                    "id": recipe.id,
                    "title": recipe.title,
                    "last_cooked": recipe.last_cooked,
                    "rating": recipe.rating,
                    "favorite": not recipe.favorite,
                    "notes": recipe.notes
                }]);
            } else {
                next_recipes = next_recipes.concat([recipe]);
            }
        }
        recipes = next_recipes;
    }

    def set_rating(recipe_id: int, rating_val: int) -> None {
        next_recipes: list = [];
        for recipe in recipes {
            if recipe.id == recipe_id {
                next_recipes = next_recipes.concat([{
                    "id": recipe.id,
                    "title": recipe.title,
                    "last_cooked": recipe.last_cooked,
                    "rating": rating_val,
                    "favorite": recipe.favorite,
                    "notes": recipe.notes
                }]);
            } else {
                next_recipes = next_recipes.concat([recipe]);
            }
        }
        recipes = next_recipes;
    }

    def generate_new_recipe() -> None {
        titles = [
            "Chickpea Curry Wrap",
            "Salmon Rice Crunch Bowl",
            "High-Protein Pasta Bake",
            "Spicy Lentil Taco Plate"
        ];
        styles = ["quick", "budget", "high-protein", "meal-prep"];

        idx = 0;
        rand_title = Math.random();
        if rand_title >= 0.75 {
            idx = 3;
        } elif rand_title >= 0.5 {
            idx = 2;
        } elif rand_title >= 0.25 {
            idx = 1;
        }

        style_idx = 0;
        rand_style = Math.random();
        if rand_style >= 0.75 {
            style_idx = 3;
        } elif rand_style >= 0.5 {
            style_idx = 2;
        } elif rand_style >= 0.25 {
            style_idx = 1;
        }
        new_recipe_idea = {
            "title": titles[idx],
            "style": styles[style_idx],
            "why": "Generated from your recent favorites and macro direction."
        };
    }

    def add_pantry_item() -> None {
        if not pantry_name.trim() {
            status_text = "Pantry item name is required.";
            return;
        }

        pantry_items = pantry_items.concat([{
            "name": pantry_name.trim(),
            "quantity": to_num(pantry_quantity, 1.0),
            "unit": pantry_unit,
            "cost": to_num(pantry_cost, 0.0),
            "protein": to_num(pantry_protein, 0.0),
            "carb": to_num(pantry_carb, 0.0),
            "fat": to_num(pantry_fat, 0.0)
        }]);

        pantry_name = "";
        pantry_quantity = "1";
        pantry_unit = "PIECE";
        pantry_cost = "0";
        pantry_protein = "0";
        pantry_carb = "0";
        pantry_fat = "0";
        status_text = "Pantry ingredient added.";
    }

    def remove_pantry_item(name: str) -> None {
        pantry_items = pantry_items.filter(
            lambda item: dict -> bool { return item.name != name; }
        );
    }

    def macro_ratio(consumed: float, target: float) -> int {
        if target <= 0 {
            return 0;
        }
        val = parseInt(((consumed * 100.0) / target).toString());
        if val < 0 {
            return 0;
        }
        if val > 100 {
            return 100;
        }
        return val;
    }

    async def generate_recipe_api() -> None {
        if pantry_items.length == 0 {
            status_text = "Add pantry items before generating recipe.";
            return;
        }

        loading = true;
        status_text = "Loading profile and generating recipe...";
        try {
            profile_result = root spawn GetUserProfile();
            profile_out = first_report_payload(profile_result);
            if not profile_out or Object.keys(profile_out).length == 0 {
                status_text = "No saved profile found. Save profile in User Profile tab first.";
                loading = false;
                return;
            }

            macro_result = root spawn GenerateUserMacroNeeds();
            macro_out = first_report_payload(macro_result);
            if macro_out.ok {
                macro_needs = macro_out;
            }

            recipe_result = root spawn GenerateRecipeFromPantry(
                profile=profile_out,
                pantry_ingredients=pantry_items
            );
            recipe_out = first_report_payload(recipe_result);
            if recipe_out.ok == false {
                status_text = "Recipe generation failed: " + String(recipe_out.error or "unknown error");
                loading = false;
                return;
            }

            generated_recipe = recipe_out;

            next_id = recipes.length + 1;
            recipes = [{
                "id": next_id,
                "title": String(recipe_out.recipe_name or "Generated Recipe"),
                "last_cooked": "Just now",
                "rating": 0,
                "favorite": false,
                "notes": "Generated from your profile + pantry"
            }].concat(recipes);

            status_text = "Recipe generated with API.";
        } except Exception as e {
            status_text = "Recipe generation failed: " + e.toString();
        }
        loading = false;
    }

    async def load_saved_recipe_api() -> None {
        loading = true;
        status_text = "Loading saved recipe...";
        try {
            result = root spawn ListGeneratedRecipe();
            out = first_report_payload(result);
            if out and Object.keys(out).length > 0 {
                generated_recipe = out;
                status_text = "Loaded saved recipe from backend.";
            } else {
                status_text = "No saved recipe found.";
            }
        } except Exception as e {
            status_text = "Load failed: " + e.toString();
        }
        loading = false;
    }

    async def clear_saved_recipe_api() -> None {
        loading = true;
        status_text = "Clearing recipe...";
        try {
            root spawn ClearGeneratedRecipe();
            generated_recipe = {};
            status_text = "Saved recipe cleared.";
        } except Exception as e {
            status_text = "Clear failed: " + e.toString();
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
                "gap": "14px"
            }}
        >
            <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "10px", "flexWrap": "wrap"}}>
                <div>
                    <h2 style={{"margin": "0"}}>Recipes</h2>
                    <p style={{"margin": "6px 0 0 0", "opacity": "0.78"}}>
                        API-wired generation using your saved profile, pantry, and macro needs.
                    </p>
                </div>
                <button onClick={generate_new_recipe} style={{"padding": "9px 12px", "borderRadius": "10px", "border": "1px solid #92400e", "background": "#fef3c7", "fontWeight": "700"}}>
                    Generate New Recipe Idea
                </button>
            </div>

            <div style={{"padding": "10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "fontWeight": "600"}}>
                {[( "Working... " if loading else "Ready. " ), status_text].join("")}
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                <button onClick={generate_recipe_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "700"}}>Generate Recipe (API)</button>
                <button onClick={load_saved_recipe_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": "#eff6ff", "fontWeight": "700"}}>Load Saved Recipe (API)</button>
                <button onClick={clear_saved_recipe_api} style={{"padding": "8px 12px", "borderRadius": "10px", "border": "1px solid #991b1b", "background": "#fee2e2", "fontWeight": "700"}}>Clear Saved Recipe (API)</button>
            </div>

            <div style={{"display": "grid", "gridTemplateColumns": "minmax(0, 1.3fr) minmax(0, 1fr)", "gap": "12px"}}>
                <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#fcfdff", "display": "grid", "gap": "10px"}}>
                    <h3 style={{"margin": "0"}}>Pantry Inputs For Recipe API</h3>
                    <div style={{"display": "grid", "gridTemplateColumns": "2fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr", "gap": "8px"}}>
                        <input value={pantry_name} onChange={lambda e: any -> None { pantry_name = e.target.value; }} placeholder="name" />
                        <input value={pantry_quantity} onChange={lambda e: any -> None { pantry_quantity = e.target.value; }} placeholder="qty" />
                        <select value={pantry_unit} onChange={lambda e: any -> None { pantry_unit = e.target.value; }}>
                            <option value="PIECE">PIECE</option>
                            <option value="LB">LB</option>
                            <option value="OZ">OZ</option>
                            <option value="CUP">CUP</option>
                            <option value="TBSP">TBSP</option>
                            <option value="TSP">TSP</option>
                            <option value="CLOVE">CLOVE</option>
                            <option value="BUNCH">BUNCH</option>
                        </select>
                        <input value={pantry_cost} onChange={lambda e: any -> None { pantry_cost = e.target.value; }} placeholder="cost" />
                        <input value={pantry_protein} onChange={lambda e: any -> None { pantry_protein = e.target.value; }} placeholder="protein" />
                        <input value={pantry_carb} onChange={lambda e: any -> None { pantry_carb = e.target.value; }} placeholder="carb" />
                        <input value={pantry_fat} onChange={lambda e: any -> None { pantry_fat = e.target.value; }} placeholder="fat" />
                        <button onClick={add_pantry_item}>Add</button>
                    </div>

                    {(
                        <div style={{"opacity": "0.75"}}>No pantry items yet.</div>
                    ) if pantry_items.length == 0 else (
                        <table style={{"width": "100%", "borderCollapse": "collapse"}}>
                            <thead>
                                <tr>
                                    <th>Name</th><th>Qty</th><th>Unit</th><th>Cost</th><th>P</th><th>C</th><th>F</th><th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {pantry_items.map(
                                    lambda item: dict -> JsxElement { return
                                        <tr key={item.name}>
                                            <td>{item.name}</td>
                                            <td>{item.quantity}</td>
                                            <td>{item.unit}</td>
                                            <td>{item.cost}</td>
                                            <td>{item.protein}</td>
                                            <td>{item.carb}</td>
                                            <td>{item.fat}</td>
                                            <td><button onClick={lambda -> None { remove_pantry_item(item.name); }}>Remove</button></td>
                                        </tr>; }
                                )}
                            </tbody>
                        </table>
                    )}
                </div>

                <div style={{"border": "1px solid #dbeafe", "borderRadius": "12px", "padding": "12px", "background": "#eff6ff"}}>
                    <h3 style={{"margin": "0 0 8px 0"}}>Macro Need Fit</h3>
                    {(
                        <div style={{"display": "grid", "gap": "8px"}}>
                            <div><b>Calories:</b> {generated_recipe.total_calories} / {macro_needs.calories_per_day}</div>
                            <div><b>Protein:</b> {generated_recipe.total_protein_g} / {macro_needs.protein_g} g ({String(macro_ratio(parseFloat(String(generated_recipe.total_protein_g or 0)), parseFloat(String(macro_needs.protein_g or 0))))}%)</div>
                            <div><b>Carbs:</b> {generated_recipe.total_carbs_g} / {macro_needs.carbs_g} g ({String(macro_ratio(parseFloat(String(generated_recipe.total_carbs_g or 0)), parseFloat(String(macro_needs.carbs_g or 0))))}%)</div>
                            <div><b>Fat:</b> {generated_recipe.total_fat_g} / {macro_needs.fat_g} g ({String(macro_ratio(parseFloat(String(generated_recipe.total_fat_g or 0)), parseFloat(String(macro_needs.fat_g or 0))))}%)</div>
                        </div>
                    ) if (Object.keys(generated_recipe).length > 0 and Object.keys(macro_needs).length > 0) else (
                        <div style={{"opacity": "0.75"}}>Generate a recipe to see macro fit against your needs.</div>
                    )}
                </div>
            </div>

            <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#fcfdff"}}>
                <h3 style={{"margin": "0 0 8px 0"}}>Generated Recipe (API)</h3>
                <pre style={{"margin": "0", "background": "#0f172a", "color": "#e2e8f0", "borderRadius": "10px", "padding": "10px", "overflowX": "auto"}}>{JSON.stringify(generated_recipe, None, 2)}</pre>
                {(
                    <ol>
                        {generated_recipe.instructions.map(
                            lambda step: str -> JsxElement { return <li key={step}>{step}</li>; }
                        )}
                    </ol>
                ) if (generated_recipe and generated_recipe.instructions and generated_recipe.instructions.length > 0) else <div /> }
            </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                <button onClick={lambda -> None { filter_mode = "all"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "all" else "#ffffff")}}>All</button>
                <button onClick={lambda -> None { filter_mode = "favorites"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "favorites" else "#ffffff")}}>Favorites</button>
                <button onClick={lambda -> None { filter_mode = "history"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "history" else "#ffffff")}}>Past Recipes</button>
            </div>

            {(
                <div style={{"padding": "10px", "border": "1px solid #fed7aa", "background": "#fff7ed", "borderRadius": "12px"}}>
                    <h3 style={{"margin": "0 0 6px 0"}}>New Recipe Suggestion</h3>
                    <div><b>{new_recipe_idea.title}</b></div>
                    <div>Style: {new_recipe_idea.style}</div>
                    <div style={{"opacity": "0.76"}}>{new_recipe_idea.why}</div>
                </div>
            ) if Object.keys(new_recipe_idea).length > 0 else <div />}

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(250px, 1fr))", "gap": "10px"}}>
                {visible_recipes().map(
                    lambda recipe: dict -> JsxElement { return
                        <div key={recipe.id.toString()} style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#fcfdff", "display": "grid", "gap": "8px"}}>
                            <div style={{"display": "flex", "justifyContent": "space-between", "gap": "8px"}}>
                                <h3 style={{"margin": "0", "fontSize": "1.05rem"}}>{recipe.title}</h3>
                                <button onClick={lambda -> None { toggle_favorite(recipe.id); }} style={{"border": "1px solid #fbcfe8", "background": "#fdf2f8", "borderRadius": "8px", "padding": "4px 8px"}}>
                                    {("★ Favorite" if recipe.favorite else "☆ Favorite")}
                                </button>
                            </div>
                            <div style={{"fontSize": "0.9rem", "opacity": "0.75"}}>Last cooked: {recipe.last_cooked}</div>
                            <div style={{"display": "flex", "gap": "6px", "alignItems": "center"}}>
                                <span style={{"fontSize": "0.9rem"}}>Rate:</span>
                                {[1, 2, 3, 4, 5].map(
                                    lambda rating_val: int -> JsxElement { return
                                        <button
                                            key={rating_val.toString()}
                                            onClick={lambda -> None { set_rating(recipe.id, rating_val); }}
                                            style={{"border": "1px solid #e2e8f0", "background": ("#fde68a" if rating_val <= recipe.rating else "#ffffff"), "borderRadius": "6px", "padding": "3px 6px"}}
                                        >
                                            {String(rating_val)}
                                        </button>; }
                                )}
                            </div>
                            <div style={{"fontSize": "0.9rem"}}><b>Notes:</b> {recipe.notes}</div>
                        </div>; }
                )}
            </div>
        </div>;
}
