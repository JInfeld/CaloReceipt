sv import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ListRecipeHistory,
    SetRecipeFavorite,
    MarkRecipeMade,
    ComputePantryAfterRecipe,
    SaveRecipeRankingBatch,
    DeleteSavedRecipe,
    ClearGeneratedRecipe
}
sv import from user {
    GetUserProfile,
    GenerateUserMacroNeeds
}

def:pub RecipesTab(
    shared_state: dict = {},
    on_auth_error: any = None,
    on_pantry_change: any = None
) -> JsxElement {
    has filter_mode: str = "all";
    has loading: bool = false;
    has status_text: str = "Recipe API ready.";

    has recipes: list = [];

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
    has active_rank_recipe_id: str = "";
    has active_rank_tier: str = "";
    has active_rank_candidates: list = [];
    has active_rank_low: int = 0;
    has active_rank_high: int = -1;
    has active_rank_mid: int = -1;
    has re_rank_recipe_id: str = "";
    has pending_rate_recipe_id: str = "";
    has show_made_confirm: bool = false;
    has expanded_recipe_id: str = "";

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

    def event_attr(e: any, attr_name: str) -> str {
        try {
            cur = e.currentTarget;
            if cur {
                raw = cur.getAttribute(attr_name);
                if raw != None {
                    return String(raw);
                }
            }
        } except Exception as _e {
            0;
        }
        try {
            tgt = e.target;
            if tgt {
                raw = tgt.getAttribute(attr_name);
                if raw != None {
                    return String(raw);
                }
            }
        } except Exception as _e {
            0;
        }
        return "";
    }

    def to_num(value: str, fallback: float = 0.0) -> float {
        parsed = parseFloat(value);
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def normalized_profile_choice(raw: any) -> str {
        return String(raw or "").trim().toUpperCase();
    }

    def profile_has_key_info(profile: dict = {}) -> bool {
        if not profile {
            return false;
        }

        age_num = parseInt(String(profile.age or "").trim());
        height_num = to_num(String(profile.height or ""), -1.0);
        weight_num = to_num(String(profile.weight or ""), -1.0);
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

    def pantry_items_ref() -> list {
        if not shared_state.pantry_items or not is_listish(shared_state.pantry_items) {
            shared_state.pantry_items = [];
        }
        return shared_state.pantry_items;
    }

    async def set_pantry_items(items: list) -> None {
        shared_state.pantry_items = items;
        if on_pantry_change {
            await on_pantry_change(items);
        }
    }

    def to_int(raw: any, fallback: int = 0) -> int {
        parsed = parseInt(String(raw));
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def norm_name(raw: any) -> str {
        return String(raw or "").trim().toLowerCase().split(" ").filter(
            lambda part: str -> bool { return part.trim().length > 0; }
        ).join(" ");
    }

    def norm_unit(raw: any) -> str {
        return String(raw or "PIECE").trim().toUpperCase();
    }

    def total_quantity_value(item: any) -> float {
        package_qty = parseFloat(String(item.package_quantity or "0").trim());
        if not isNaN(package_qty) and package_qty > 0.0 {
            return package_qty;
        }
        serving_qty = parseFloat(String(item.quantity or "0").trim());
        if not isNaN(serving_qty) and serving_qty > 0.0 {
            return serving_qty;
        }
        return 0.0;
    }

    def total_quantity_unit(item: any) -> str {
        package_unit = norm_unit(item.package_unit);
        if package_unit != "PIECE" or total_quantity_value(item) > 0.0 {
            if String(item.package_unit or "").trim().length > 0 {
                return package_unit;
            }
        }
        return norm_unit(item.unit);
    }

    def serving_size_display(item: any) -> str {
        serving_text = String(item.serving_size or "").trim();
        if serving_text.length > 0 {
            return serving_text;
        }
        unit_text = norm_unit(item.unit);
        if unit_text == "PIECE" {
            return "1 piece";
        }
        if unit_text == "TBSP" {
            return "1 tbsp";
        }
        if unit_text == "TSP" {
            return "1 tsp";
        }
        if unit_text == "CUP" {
            return "1 cup";
        }
        if unit_text == "CLOVE" {
            return "1 clove";
        }
        if unit_text == "BUNCH" {
            return "1 bunch";
        }
        if unit_text == "OZ" {
            return "1 oz";
        }
        if unit_text == "LB" {
            return "1 lb";
        }
        return "-";
    }

    def round_two(value: float) -> float {
        return Math.round(value * 100.0) / 100.0;
    }

    def singular_food_token(token: str) -> str {
        clean = String(token or "").trim().toLowerCase();
        if clean.endsWith("ies") and clean.length > 3 {
            return clean.slice(0, clean.length - 3) + "y";
        }
        if clean.endsWith("es") and clean.length > 3 {
            return clean.slice(0, clean.length - 2);
        }
        if clean.endsWith("s") and clean.length > 3 {
            return clean.slice(0, clean.length - 1);
        }
        return clean;
    }

    def food_name_tokens(raw: any) -> list {
        stop_words = [
            "fresh", "organic", "whole", "plain", "raw", "boneless", "skinless",
            "low", "sodium", "reduced", "fat", "free", "light", "natural"
        ];
        return norm_name(raw).split(" ").map(
            lambda token: str -> str : singular_food_token(token)
        ).filter(
            lambda token: str -> bool {
                return token.length > 0 and stop_words.indexOf(token) < 0;
            }
        );
    }

    def food_name_match_score(left: any, right: any) -> float {
        left_norm = norm_name(left);
        right_norm = norm_name(right);
        if left_norm.length == 0 or right_norm.length == 0 {
            return 0.0;
        }
        if left_norm == right_norm {
            return 100.0;
        }
        if left_norm.includes(right_norm) or right_norm.includes(left_norm) {
            return 85.0;
        }

        left_tokens = food_name_tokens(left);
        right_tokens = food_name_tokens(right);
        if left_tokens.length == 0 or right_tokens.length == 0 {
            return 0.0;
        }

        shared_count = 0;
        for token in left_tokens {
            if right_tokens.indexOf(token) >= 0 {
                shared_count = shared_count + 1;
            }
        }
        if shared_count == 0 {
            return 0.0;
        }

        return (
            (shared_count * 60.0) / left_tokens.length +
            (shared_count * 40.0) / right_tokens.length
        );
    }

    def unit_group(unit_text: str) -> str {
        if unit_text == "LB" or unit_text == "OZ" {
            return "mass";
        }
        if unit_text == "CUP" or unit_text == "TBSP" or unit_text == "TSP" {
            return "volume";
        }
        return unit_text;
    }

    def unit_factor(unit_text: str) -> float {
        if unit_text == "LB" {
            return 16.0;
        }
        if unit_text == "OZ" {
            return 1.0;
        }
        if unit_text == "CUP" {
            return 48.0;
        }
        if unit_text == "TBSP" {
            return 3.0;
        }
        if unit_text == "TSP" {
            return 1.0;
        }
        if unit_text == "PIECE" or unit_text == "CLOVE" or unit_text == "BUNCH" {
            return 1.0;
        }
        return 0.0;
    }

    def convert_quantity(quantity: float, from_unit_raw: any, to_unit_raw: any) -> float {
        from_unit = norm_unit(from_unit_raw);
        to_unit = norm_unit(to_unit_raw);
        if quantity < 0.0 {
            return -1.0;
        }
        if from_unit == to_unit {
            return quantity;
        }
        if unit_group(from_unit) != unit_group(to_unit) {
            return -1.0;
        }
        from_factor = unit_factor(from_unit);
        to_factor = unit_factor(to_unit);
        if from_factor <= 0.0 or to_factor <= 0.0 {
            return -1.0;
        }
        return (quantity * from_factor) / to_factor;
    }

    def legacy_rating_to_scale(raw_rating: float) -> float {
        if raw_rating >= 4.5 {
            return 10.0;
        }
        if raw_rating >= 3.5 {
            return 8.5;
        }
        if raw_rating >= 2.5 {
            return 5.5;
        }
        if raw_rating >= 1.5 {
            return 2.5;
        }
        if raw_rating > 0 {
            return 1.0;
        }
        return 0.0;
    }

    def tier_min_rating(tier: str) -> float {
        if tier == "very_good" {
            return 7.0;
        }
        if tier == "average" {
            return 4.0;
        }
        if tier == "not_great" {
            return 1.0;
        }
        return 0.0;
    }

    def tier_max_rating(tier: str) -> float {
        if tier == "very_good" {
            return 10.0;
        }
        if tier == "average" {
            return 6.9;
        }
        if tier == "not_great" {
            return 3.9;
        }
        return 0.0;
    }

    def tier_label(tier: str) -> str {
        if tier == "very_good" {
            return "Very Good";
        }
        if tier == "average" {
            return "Average";
        }
        if tier == "not_great" {
            return "Not Great";
        }
        return "Unranked";
    }

    def tier_priority(tier: str) -> int {
        if tier == "very_good" {
            return 0;
        }
        if tier == "average" {
            return 1;
        }
        if tier == "not_great" {
            return 2;
        }
        return 3;
    }

    def clamp_rating(value: float, min_val: float, max_val: float) -> float {
        if value < min_val {
            return min_val;
        }
        if value > max_val {
            return max_val;
        }
        return value;
    }

    def round_rating(value: float) -> float {
        return Math.round(value * 10.0) / 10.0;
    }

    def recipe_rating_value(recipe: dict) -> float {
        raw_rating = to_num(String(recipe.rating or "0"), 0.0);
        raw_tier = String(recipe.rating_tier or "").trim().toLowerCase();
        if raw_tier == "" and raw_rating > 0 and raw_rating <= 5.0 {
            return legacy_rating_to_scale(raw_rating);
        }
        return raw_rating;
    }

    def recipe_tier(recipe: dict) -> str {
        raw_tier = String(recipe.rating_tier or "").trim().toLowerCase();
        if raw_tier == "very_good" or raw_tier == "average" or raw_tier == "not_great" {
            return raw_tier;
        }
        score = recipe_rating_value(recipe);
        if score >= 7.0 {
            return "very_good";
        }
        if score >= 4.0 {
            return "average";
        }
        if score > 0.0 {
            return "not_great";
        }
        return "";
    }

    def rating_order_value(recipe: dict) -> int {
        return to_int(recipe.rating_order, -1);
    }

    def generated_time_value(recipe: dict) -> int {
        return to_int(recipe.generated_at_ms, 0);
    }

    def made_time_value(recipe: dict) -> int {
        return to_int(recipe.made_at_ms, 0);
    }

    def clone_recipe_instructions(raw: any) -> list {
        if not is_listish(raw) {
            return [];
        }
        return raw.map(
            lambda step: any -> str { return String(step or "").trim(); }
        ).filter(
            lambda step: str -> bool { return step.length > 0; }
        );
    }

    def clone_recipe_ingredients(raw: any) -> list {
        if not is_listish(raw) {
            return [];
        }
        return raw.map(
            lambda item: dict -> dict { return
                {
                    "name": String(item.name or "").trim(),
                    "quantity": to_num(String(item.quantity or "0"), 0.0),
                    "unit": norm_unit(item.unit),
                    "cost": to_num(String(item.cost or "0"), 0.0),
                    "protein": to_num(String(item.protein or "0"), 0.0),
                    "carb": to_num(String(item.carb or "0"), 0.0),
                    "fat": to_num(String(item.fat or "0"), 0.0),
                    "serving_size": String(item.serving_size or "").trim(),
                    "package_quantity": to_num(String(item.package_quantity or "0"), 0.0),
                    "package_unit": norm_unit(item.package_unit)
                }; }
        ).filter(
            lambda item: dict -> bool { return String(item.name or "").trim().length > 0; }
        );
    }

    def clone_recipe(recipe: dict) -> dict {
        return {
            "recipe_id": String(recipe.recipe_id or ""),
            "recipe_key": recipe_lookup_key(recipe),
            "title": String(recipe.title or recipe.recipe_name or ""),
            "total_calories": to_num(String(recipe.total_calories or "0"), 0.0),
            "total_protein_g": to_num(String(recipe.total_protein_g or "0"), 0.0),
            "total_carbs_g": to_num(String(recipe.total_carbs_g or "0"), 0.0),
            "total_fat_g": to_num(String(recipe.total_fat_g or "0"), 0.0),
            "generated_at_ms": generated_time_value(recipe),
            "rating": recipe_rating_value(recipe),
            "rating_tier": recipe_tier(recipe),
            "rating_order": rating_order_value(recipe),
            "favorite": (true if recipe.favorite else false),
            "made": (true if recipe.made else false),
            "made_at_ms": made_time_value(recipe),
            "notes": String(recipe.notes or "Generated from your profile + pantry"),
            "instructions": clone_recipe_instructions(recipe.instructions),
            "ingredients": clone_recipe_ingredients(recipe.ingredients)
        };
    }

    def sort_ranked_recipes(list_in: list) -> list {
        return list_in.slice().sort(
            lambda left: dict, right: dict -> int {
                left_order = rating_order_value(left);
                right_order = rating_order_value(right);
                if left_order >= 0 and right_order >= 0 and left_order != right_order {
                    return left_order - right_order;
                }
                left_rating = recipe_rating_value(left);
                right_rating = recipe_rating_value(right);
                if left_rating != right_rating {
                    return Math.round((right_rating - left_rating) * 100.0);
                }
                return generated_time_value(right) - generated_time_value(left);
            }
        );
    }

    def legacy_recipe_key(title: any, generated_at_ms: any) -> str {
        clean_title = norm_name(title);
        stamp = to_int(generated_at_ms, 0);
        return ["legacy", String(stamp), clean_title].join("::");
    }

    def recipe_lookup_key(recipe: dict) -> str {
        recipe_id = String(recipe.recipe_id or "").trim();
        if recipe_id != "" {
            return recipe_id;
        }
        return legacy_recipe_key(
            String(recipe.title or recipe.recipe_name or ""),
            recipe.generated_at_ms
        );
    }

    def row_lookup_key(row: dict) -> str {
        recipe_key = String(row.recipe_key or "").trim();
        if recipe_key != "" {
            return recipe_key;
        }
        recipe_id = String(row.recipe_id or "").trim();
        if recipe_id != "" {
            return recipe_id;
        }
        return legacy_recipe_key(
            String(row.title or row.recipe_name or ""),
            row.generated_at_ms
        );
    }

    def tier_recipes_sorted(tier: str, exclude_recipe_id: str = "") -> list {
        return sort_ranked_recipes(
            recipes.filter(
                lambda recipe: dict -> bool {
                    return (
                        recipe_tier(recipe) == tier and
                        recipe_lookup_key(recipe) != exclude_recipe_id
                    );
                }
            )
        );
    }

    def score_for_tier_position(tier: str, position: int, total: int) -> float {
        min_score = tier_min_rating(tier);
        max_score = tier_max_rating(tier);
        if total <= 0 {
            return 0.0;
        }
        if total == 1 {
            return round_rating((min_score + max_score) / 2.0);
        }
        step = (max_score - min_score) / (total - 1);
        return round_rating(clamp_rating(max_score - (position * step), min_score, max_score));
    }

    def build_rank_updates_for_tier(tier: str, ranked_recipes: list) -> list {
        updates: list = [];
        total = ranked_recipes.length;
        for idx=0 to idx<total by idx+=1 {
            ranked_recipe = ranked_recipes[idx];
            updates = updates.concat([{
                "recipe_id": String(ranked_recipe.recipe_id or ""),
                "recipe_key": recipe_lookup_key(ranked_recipe),
                "title": String(ranked_recipe.title or ""),
                "generated_at_ms": generated_time_value(ranked_recipe),
                "rating": 0.0,
                "rating_tier": tier,
                "rating_order": idx
            }]);
        }
        return updates;
    }

    def apply_rank_updates(base_recipes: list, updates: list) -> list {
        update_map: dict = {};
        for row in updates {
            update_map[row_lookup_key(row)] = row;
        }
        next_recipes: list = [];
        for recipe in base_recipes {
            recipe_id = recipe_lookup_key(recipe);
            row = update_map[recipe_id] or None;
            next_recipe = clone_recipe(recipe);
            if row != None {
                if String(row.recipe_id or "").trim() != "" {
                    next_recipe.recipe_id = String(row.recipe_id or "").trim();
                }
                next_recipe.recipe_key = row_lookup_key(row);
                next_recipe.rating = to_num(String(row.rating or "0"), 0.0);
                next_recipe.rating_tier = String(row.rating_tier or "").trim().toLowerCase();
                next_recipe.rating_order = to_int(row.rating_order, -1);
            }
            next_recipes = next_recipes.concat([next_recipe]);
        }
        return next_recipes;
    }

    def clear_ranking_session() -> None {
        active_rank_recipe_id = "";
        active_rank_tier = "";
        active_rank_candidates = [];
        active_rank_low = 0;
        active_rank_high = -1;
        active_rank_mid = -1;
        re_rank_recipe_id = "";
    }

    def current_rank_comparison() -> dict {
        if active_rank_mid < 0 or active_rank_mid >= active_rank_candidates.length {
            return {};
        }
        return active_rank_candidates[active_rank_mid];
    }

    def rank_comparison_from(candidates: list, mid: int) -> dict {
        if mid < 0 or mid >= candidates.length {
            return {};
        }
        return candidates[mid];
    }

    def show_rank_controls(recipe: dict) -> bool {
        recipe_key = recipe_lookup_key(recipe);
        if active_rank_recipe_id == recipe_key {
            return true;
        }
        if recipe_tier(recipe) == "" {
            return true;
        }
        return re_rank_recipe_id == recipe_key;
    }

    def rating_display_text(recipe: dict) -> str {
        score = recipe_rating_value(recipe);
        if score <= 0.0 {
            return "Not Ranked";
        }
        return String(score.toFixed(1));
    }

    def rating_intensity(recipe: dict) -> float {
        tier = recipe_tier(recipe);
        if tier == "" {
            return 0.0;
        }
        min_score = tier_min_rating(tier);
        max_score = tier_max_rating(tier);
        if max_score <= min_score {
            return 0.0;
        }
        return clamp_rating((recipe_rating_value(recipe) - min_score) / (max_score - min_score), 0.0, 1.0);
    }

    def rating_badge_style(recipe: dict) -> dict {
        tier = recipe_tier(recipe);
        intensity = rating_intensity(recipe);
        alpha = (0.20 + (intensity * 0.55)).toFixed(2);
        border_alpha = (0.35 + (intensity * 0.45)).toFixed(2);
        if tier == "very_good" {
            return {
                "display": "inline-flex",
                "alignItems": "center",
                "justifyContent": "center",
                "minWidth": "74px",
                "padding": "6px 10px",
                "borderRadius": "999px",
                "fontWeight": "800",
                "background": "rgba(34, 197, 94, " + alpha + ")",
                "border": "1px solid rgba(21, 128, 61, " + border_alpha + ")",
                "color": "#14532d"
            };
        }
        if tier == "average" {
            return {
                "display": "inline-flex",
                "alignItems": "center",
                "justifyContent": "center",
                "minWidth": "74px",
                "padding": "6px 10px",
                "borderRadius": "999px",
                "fontWeight": "800",
                "background": "rgba(250, 204, 21, " + alpha + ")",
                "border": "1px solid rgba(161, 98, 7, " + border_alpha + ")",
                "color": "#713f12"
            };
        }
        if tier == "not_great" {
            return {
                "display": "inline-flex",
                "alignItems": "center",
                "justifyContent": "center",
                "minWidth": "74px",
                "padding": "6px 10px",
                "borderRadius": "999px",
                "fontWeight": "800",
                "background": "rgba(239, 68, 68, " + alpha + ")",
                "border": "1px solid rgba(185, 28, 28, " + border_alpha + ")",
                "color": "#7f1d1d"
            };
        }
        return {
            "display": "inline-flex",
            "alignItems": "center",
            "justifyContent": "center",
            "minWidth": "92px",
            "padding": "6px 10px",
            "borderRadius": "999px",
            "fontWeight": "700",
            "background": "#f8fafc",
            "border": "1px solid #cbd5e1",
            "color": "#475569"
        };
    }

    def tier_chip_style(tier: str) -> dict {
        if tier == "very_good" {
            return {"padding": "4px 9px", "borderRadius": "999px", "border": "1px solid #86efac", "background": "#dcfce7", "color": "#166534", "fontWeight": "700", "fontSize": "0.84rem"};
        }
        if tier == "average" {
            return {"padding": "4px 9px", "borderRadius": "999px", "border": "1px solid #fcd34d", "background": "#fef3c7", "color": "#92400e", "fontWeight": "700", "fontSize": "0.84rem"};
        }
        if tier == "not_great" {
            return {"padding": "4px 9px", "borderRadius": "999px", "border": "1px solid #fca5a5", "background": "#fee2e2", "color": "#991b1b", "fontWeight": "700", "fontSize": "0.84rem"};
        }
        return {"padding": "4px 9px", "borderRadius": "999px", "border": "1px solid #cbd5e1", "background": "#f8fafc", "color": "#475569", "fontWeight": "700", "fontSize": "0.84rem"};
    }

    def tier_button_style(tier: str, is_active: bool = false) -> dict {
        if tier == "very_good" {
            return {
                "padding": "8px 10px",
                "borderRadius": "10px",
                "border": ("2px solid #15803d" if is_active else "1px solid #86efac"),
                "background": ("#22c55e" if is_active else "#dcfce7"),
                "color": ("#f0fdf4" if is_active else "#166534"),
                "fontWeight": "800"
            };
        }
        if tier == "average" {
            return {
                "padding": "8px 10px",
                "borderRadius": "10px",
                "border": ("2px solid #a16207" if is_active else "1px solid #fcd34d"),
                "background": ("#f59e0b" if is_active else "#fef3c7"),
                "color": ("#fffbeb" if is_active else "#92400e"),
                "fontWeight": "800"
            };
        }
        return {
            "padding": "8px 10px",
            "borderRadius": "10px",
            "border": ("2px solid #b91c1c" if is_active else "1px solid #fca5a5"),
            "background": ("#ef4444" if is_active else "#fee2e2"),
            "color": ("#fef2f2" if is_active else "#991b1b"),
            "fontWeight": "800"
        };
    }

    def visible_recipes() -> list {
        if not is_listish(recipes) {
            return [];
        }
        ordered = recipes.slice().sort(
            lambda left: dict, right: dict -> int {
                left_tier = recipe_tier(left);
                right_tier = recipe_tier(right);
                tier_diff = tier_priority(left_tier) - tier_priority(right_tier);
                if tier_diff != 0 {
                    return tier_diff;
                }
                if left_tier != "" or right_tier != "" {
                    left_order = rating_order_value(left);
                    right_order = rating_order_value(right);
                    if left_order >= 0 and right_order >= 0 and left_order != right_order {
                        return left_order - right_order;
                    }
                    rating_diff = Math.round((recipe_rating_value(right) - recipe_rating_value(left)) * 100.0);
                    if rating_diff != 0 {
                        return rating_diff;
                    }
                }
                return generated_time_value(right) - generated_time_value(left);
            }
        );
        if filter_mode == "favorites" {
            return ordered.filter(
                lambda recipe: dict -> bool { return recipe.favorite; }
            );
        }
        if filter_mode == "history" {
            return ordered.filter(
                lambda recipe: dict -> bool { return recipe.made; }
            );
        }
        return ordered;
    }

    def format_saved_time(recipe: dict) -> str {
        raw_ms = parseInt(String(recipe.generated_at_ms or 0));
        if isNaN(raw_ms) or raw_ms <= 0 {
            return "Unknown";
        }
        stamp = Reflect.construct(Date, [raw_ms]);
        return stamp.toLocaleString();
    }

    def format_made_time(recipe: dict) -> str {
        raw_ms = to_int(recipe.made_at_ms, 0);
        if raw_ms <= 0 {
            return "Not made yet";
        }
        stamp = Reflect.construct(Date, [raw_ms]);
        return stamp.toLocaleString();
    }

    def recipe_by_id(recipe_id: str) -> dict {
        for recipe in recipes {
            if recipe_lookup_key(recipe) == recipe_id {
                return recipe;
            }
        }
        return {};
    }

    def recipe_details_open(recipe: dict) -> bool {
        return expanded_recipe_id == recipe_lookup_key(recipe);
    }

    def generated_recipe_history_entry() -> dict {
        recipe_id = String(generated_recipe.recipe_id or "");
        if recipe_id == "" {
            return {};
        }
        return recipe_by_id(recipe_id);
    }

    def history_entry_from_generated_recipe(recipe_id: str, made_at_ms: int = 0, made: bool = false) -> dict {
        return {
            "recipe_id": recipe_id,
            "title": String(generated_recipe.recipe_name or generated_recipe.title or "Generated Recipe"),
            "total_calories": to_num(String(generated_recipe.total_calories or "0"), 0.0),
            "total_protein_g": to_num(String(generated_recipe.total_protein_g or "0"), 0.0),
            "total_carbs_g": to_num(String(generated_recipe.total_carbs_g or "0"), 0.0),
            "total_fat_g": to_num(String(generated_recipe.total_fat_g or "0"), 0.0),
            "generated_at_ms": to_int(generated_recipe.generated_at_ms, now_ms()),
            "rating": 0.0,
            "rating_tier": "",
            "rating_order": -1,
            "favorite": false,
            "made": made,
            "made_at_ms": (made_at_ms if made else 0),
            "notes": "Generated from your profile + pantry",
            "instructions": clone_recipe_instructions(generated_recipe.instructions),
            "ingredients": clone_recipe_ingredients(generated_recipe.ingredients)
        };
    }

    def replace_recipe_in_list(updated_recipe: dict) -> None {
        next_recipes: list = [];
        replaced = false;
        target_id = String(updated_recipe.recipe_id or "");
        for recipe in recipes {
            if String(recipe.recipe_id or "") == target_id {
                next_recipes = next_recipes.concat([updated_recipe]);
                replaced = true;
            } else {
                next_recipes = next_recipes.concat([recipe]);
            }
        }
        if not replaced and Object.keys(updated_recipe).length > 0 {
            next_recipes = next_recipes.concat([updated_recipe]);
        }
        recipes = next_recipes;
    }

    def remove_recipe_from_list(recipe_id: str) -> None {
        recipes = recipes.filter(
            lambda recipe: dict -> bool { return String(recipe.recipe_id or "") != recipe_id; }
        );
        if expanded_recipe_id == recipe_id {
            expanded_recipe_id = "";
        }
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

    async def add_pantry_item() -> None {
        if not pantry_name.trim() {
            status_text = "Pantry item name is required.";
            return;
        }

        await set_pantry_items(pantry_items_ref().concat([{
            "name": pantry_name.trim(),
            "quantity": to_num(pantry_quantity, 1.0),
            "unit": pantry_unit,
            "cost": to_num(pantry_cost, 0.0),
            "protein": to_num(pantry_protein, 0.0),
            "carb": to_num(pantry_carb, 0.0),
            "fat": to_num(pantry_fat, 0.0),
            "serving_size": ["1 ", pantry_unit].join(""),
            "package_quantity": to_num(pantry_quantity, 1.0),
            "package_unit": pantry_unit
        }]));

        pantry_name = "";
        pantry_quantity = "1";
        pantry_unit = "PIECE";
        pantry_cost = "0";
        pantry_protein = "0";
        pantry_carb = "0";
        pantry_fat = "0";
        status_text = "Pantry ingredient added as per-serving storage.";
    }

    async def remove_pantry_item(name: str) -> None {
        await set_pantry_items(
            pantry_items_ref().filter(
                lambda item: dict -> bool { return item.name != name; }
            )
        );
    }

    async def handle_remove_pantry_item_click(e: any) -> None {
        item_name = event_attr(e, "data-item-name").trim();
        if item_name == "" {
            return;
        }
        await remove_pantry_item(item_name);
    }

    def next_pantry_after_recipe(recipe_ingredients: list) -> list {
        next_pantry = pantry_items_ref().map(
            lambda item: dict -> dict { return
                {
                    "name": String(item.name or ""),
                    "quantity": to_num(String(item.quantity or "0"), 0.0),
                    "unit": norm_unit(item.unit),
                    "cost": to_num(String(item.cost or "0"), 0.0),
                    "protein": to_num(String(item.protein or "0"), 0.0),
                    "carb": to_num(String(item.carb or "0"), 0.0),
                    "fat": to_num(String(item.fat or "0"), 0.0),
                    "serving_size": String(item.serving_size or "").trim(),
                    "package_quantity": to_num(String(item.package_quantity or "0"), 0.0),
                    "package_unit": norm_unit(item.package_unit)
                }; }
        );

        for ingredient in recipe_ingredients {
            remaining_qty = to_num(String(ingredient.quantity or "0"), 0.0);
            if remaining_qty <= 0.0 {
                continue;
            }
            ingredient_name = String(ingredient.name or "");
            ingredient_unit = norm_unit(ingredient.unit);
            while remaining_qty > 0.0001 {
                best_idx = -1;
                best_score = 0.0;
                best_needed_qty = -1.0;
                idx = 0;
                for item in next_pantry {
                    item_qty = to_num(String(item.quantity or "0"), 0.0);
                    needed_in_item_unit = convert_quantity(remaining_qty, ingredient_unit, item.unit);
                    if item_qty > 0.0 and needed_in_item_unit > 0.0 {
                        match_score = food_name_match_score(ingredient_name, item.name);
                        if match_score > best_score {
                            best_idx = idx;
                            best_score = match_score;
                            best_needed_qty = needed_in_item_unit;
                        }
                    }
                    idx = idx + 1;
                }
                if best_idx < 0 or best_score < 55.0 or best_needed_qty <= 0.0 {
                    break;
                }

                updated_pantry: list = [];
                idx = 0;
                used_any = false;
                for item in next_pantry {
                    if idx == best_idx {
                        item_qty = to_num(String(item.quantity or "0"), 0.0);
                        used_qty = best_needed_qty;
                        if used_qty > item_qty {
                            used_qty = item_qty;
                        }
                        consumed_recipe_qty = convert_quantity(used_qty, item.unit, ingredient_unit);
                        remaining_item_qty = item_qty - used_qty;
                        if consumed_recipe_qty > 0.0 {
                            remaining_qty = remaining_qty - consumed_recipe_qty;
                            used_any = true;
                        }
                        if remaining_item_qty > 0.0001 and item_qty > 0.0 {
                            remaining_package_qty = to_num(String(item.package_quantity or "0"), 0.0);
                            if remaining_package_qty > 0.0 {
                                remaining_package_qty = remaining_package_qty * (remaining_item_qty / item_qty);
                            }
                            updated_pantry = updated_pantry.concat([{
                                "name": item.name,
                                "quantity": round_two(remaining_item_qty),
                                "unit": norm_unit(item.unit),
                                "cost": round_two(to_num(String(item.cost or "0"), 0.0)),
                                "protein": round_two(to_num(String(item.protein or "0"), 0.0)),
                                "carb": round_two(to_num(String(item.carb or "0"), 0.0)),
                                "fat": round_two(to_num(String(item.fat or "0"), 0.0)),
                                "serving_size": String(item.serving_size or "").trim(),
                                "package_quantity": round_two(remaining_package_qty),
                                "package_unit": norm_unit(item.package_unit)
                            }]);
                        }
                    } else {
                        updated_pantry = updated_pantry.concat([item]);
                    }
                    idx = idx + 1;
                }
                next_pantry = updated_pantry;
                if not used_any {
                    break;
                }
            }
        }

        return next_pantry;
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

    async def complete_recipe_and_update_pantry(recipe: dict, clear_generated_after: bool = false) -> bool {
        recipe_id = recipe_lookup_key(recipe);
        recipe_ingredients = clone_recipe_ingredients(recipe.ingredients);
        if recipe_id == "" {
            status_text = "Recipe is missing an id.";
            return false;
        }
        if recipe_ingredients.length == 0 {
            status_text = "This recipe does not have ingredient data to remove from pantry.";
            return false;
        }

        loading = true;
        status_text = ("Updating pantry for this saved recipe..." if recipe.made else "Removing used ingredients and saving recipe progress...");
        previous_pantry = pantry_items_ref().slice();
        next_pantry = next_pantry_after_recipe(recipe_ingredients);
        pantry_match_note = "";
        made_at_ms = now_ms();

        try {
            try {
                subtract_result = root spawn ComputePantryAfterRecipe(
                    pantry_items=pantry_items_ref(),
                    recipe_ingredients=recipe_ingredients
                );
                subtract_out = first_report_payload(subtract_result);
                if subtract_out and subtract_out.ok and is_listish(subtract_out.updated_pantry) {
                    next_pantry = subtract_out.updated_pantry;
                    pantry_match_note = String(subtract_out.notes or "");
                } elif subtract_out and subtract_out.error {
                    pantry_match_note = "Used direct pantry subtraction fallback: " + String(subtract_out.error);
                }
            } except Exception as subtract_e {
                pantry_match_note = "Used direct pantry subtraction fallback: " + subtract_e.toString();
            }

            await set_pantry_items(next_pantry);
            result = root spawn MarkRecipeMade(
                recipe_id=recipe_id,
                made=True,
                made_at_ms=made_at_ms
            );
            out = first_report_payload(result);
            if not out or out.updated == false {
                await set_pantry_items(previous_pantry);
                err_text = String((out.error if out else "Recipe update failed."));
                status_text = "Could not mark recipe as made: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return false;
            }

            await load_recipe_history_api(True);
            updated_recipe = recipe_by_id(recipe_id);
            if not updated_recipe or Object.keys(updated_recipe).length == 0 {
                updated_recipe = clone_recipe(recipe);
            } else {
                updated_recipe = clone_recipe(updated_recipe);
            }
            updated_recipe.made = true;
            updated_recipe.made_at_ms = made_at_ms;
            if clone_recipe_instructions(updated_recipe.instructions).length == 0 {
                updated_recipe.instructions = clone_recipe_instructions(recipe.instructions);
            }
            if clone_recipe_ingredients(updated_recipe.ingredients).length == 0 {
                updated_recipe.ingredients = recipe_ingredients;
            }
            replace_recipe_in_list(updated_recipe);

            if out and out.cleared_generated and String(generated_recipe.recipe_id or "") == recipe_id {
                generated_recipe = {};
                show_made_confirm = false;
            } elif String(generated_recipe.recipe_id or "") == recipe_id {
                generated_recipe.made = true;
                generated_recipe.made_at_ms = made_at_ms;
            }
            if clear_generated_after and String(generated_recipe.recipe_id or "") == recipe_id {
                generated_recipe = {};
                show_made_confirm = false;
            }

            pending_rate_recipe_id = recipe_id;
            expanded_recipe_id = recipe_id;
            filter_mode = "history";
            status_text = (
                "Recipe made again, pantry updated, and rating prompt is ready below."
                if recipe.made
                else "Recipe added to Past Recipes, pantry updated, and rating prompt is ready below."
            );
            if pantry_match_note.trim().length > 0 {
                status_text = [status_text, " ", pantry_match_note].join("");
            }
            loading = false;
            return true;
        } except Exception as e {
            await set_pantry_items(previous_pantry);
            err_text = e.toString();
            status_text = "Could not mark recipe as made: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
        return false;
    }

    async def mark_generated_recipe_made() -> None {
        recipe_id = String(generated_recipe.recipe_id or "");
        if recipe_id == "" {
            status_text = "Generate or load a recipe first.";
            return;
        }
        if not generated_recipe.ingredients or not is_listish(generated_recipe.ingredients) or generated_recipe.ingredients.length == 0 {
            status_text = "This recipe does not have ingredient data to remove from pantry.";
            return;
        }

        recipe = generated_recipe_history_entry();
        if recipe.made {
            show_made_confirm = false;
            pending_rate_recipe_id = recipe_id;
            filter_mode = "history";
            status_text = "Recipe is already in Past Recipes. Use the saved recipe card below to make it again.";
            return;
        }

        show_made_confirm = false;
        completion_recipe = (
            clone_recipe(recipe)
            if recipe and Object.keys(recipe).length > 0
            else history_entry_from_generated_recipe(recipe_id)
        );
        await complete_recipe_and_update_pantry(completion_recipe, true);
    }

    async def generate_recipe_api() -> None {
        if pantry_items_ref().length == 0 {
            status_text = "Add pantry items before generating recipe.";
            return;
        }

        loading = true;
        status_text = "Loading profile and generating recipe...";
        try {
            profile_result = root spawn GetUserProfile();
            profile_out = first_report_payload(profile_result);
            if profile_out and profile_out.error {
                err_text = String(profile_out.error);
                status_text = "Profile lookup failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }
            if not profile_has_key_info(profile_out) {
                status_text = "Profile is missing required information. Finish it in User Profile first.";
                loading = false;
                return;
            }

            macro_result = root spawn GenerateUserMacroNeeds();
            macro_out = first_report_payload(macro_result);
            if macro_out.ok {
                macro_needs = macro_out;
            } elif macro_out and macro_out.error {
                maybe_trigger_auth_error(String(macro_out.error));
            }

            recipe_result = root spawn GenerateRecipeFromPantry(
                profile=profile_out,
                pantry_ingredients=pantry_items_ref()
            );
            recipe_out = first_report_payload(recipe_result);
            if recipe_out.ok == false {
                err_text = String(recipe_out.error or "unknown error");
                status_text = "Recipe generation failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }

            generated_recipe = recipe_out;
            show_made_confirm = false;
            await load_recipe_history_api(True);

            status_text = "Recipe generated with API.";
        } except Exception as e {
            err_text = e.toString();
            status_text = "Recipe generation failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async def load_saved_macro_needs() -> None {
        try {
            macro_result = root spawn GenerateUserMacroNeeds();
            macro_out = first_report_payload(macro_result);
            if macro_out and macro_out.ok {
                macro_needs = macro_out;
            } elif macro_out and macro_out.error {
                maybe_trigger_auth_error(String(macro_out.error));
            }
        } except Exception as e {
            maybe_trigger_auth_error(e.toString());
        }
    }

    async def load_recipe_history_api(silent: bool = False) -> None {
        if not silent {
            loading = true;
            status_text = "Loading saved recipe history...";
        }
        try {
            result = root spawn ListRecipeHistory();
            out = first_report_payload(result);
            if is_listish(out) {
                recipes = out.map(
                    lambda recipe: dict -> dict { return clone_recipe(recipe); }
                );
            } else {
                recipes = [];
            }
            if expanded_recipe_id != "" and Object.keys(recipe_by_id(expanded_recipe_id)).length == 0 {
                expanded_recipe_id = "";
            }
            clear_ranking_session();
            if not silent {
                status_text = ["Loaded ", String(recipes.length), " saved recipes."].join("");
            }
        } except Exception as e {
            err_text = e.toString();
            if not silent {
                status_text = "History load failed: " + err_text;
            }
            maybe_trigger_auth_error(err_text);
        }
        if not silent {
            loading = false;
        }
    }

    async def toggle_favorite(recipe_id: str) -> None {
        recipe = recipe_by_id(recipe_id);
        if not recipe or Object.keys(recipe).length == 0 {
            status_text = "Recipe not found.";
            return;
        }

        loading = true;
        status_text = "Saving favorite status...";
        try {
            next_recipe = clone_recipe(recipe);
            next_recipe.favorite = (false if recipe.favorite else true);
            replace_recipe_in_list(next_recipe);
            result = root spawn SetRecipeFavorite(
                recipe_id=recipe_id,
                favorite=next_recipe.favorite
            );
            out = first_report_payload(result);
            if out and out.updated == false {
                err_text = String(out.error or "Recipe update failed.");
                replace_recipe_in_list(recipe);
                status_text = "Favorite update failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }
            status_text = "Favorite status saved.";
        } except Exception as e {
            replace_recipe_in_list(recipe);
            err_text = e.toString();
            status_text = "Favorite update failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async def handle_saved_recipe_favorite_click(e: any) -> None {
        recipe_id = event_attr(e, "data-recipe-id").trim();
        if recipe_id == "" {
            return;
        }
        await toggle_favorite(recipe_id);
    }

    async def finalize_recipe_ranking(recipe_id: str, tier: str, insert_index: int) -> None {
        recipe = recipe_by_id(recipe_id);
        if not recipe or Object.keys(recipe).length == 0 {
            clear_ranking_session();
            status_text = "Recipe not found.";
            return;
        }

        source_tier = recipe_tier(recipe);
        destination_ranked = tier_recipes_sorted(tier, recipe_id);
        if insert_index < 0 {
            insert_index = 0;
        }
        if insert_index > destination_ranked.length {
            insert_index = destination_ranked.length;
        }

        destination_with_target = destination_ranked.slice(0, insert_index).concat([clone_recipe(recipe)]).concat(destination_ranked.slice(insert_index));
        rank_updates = build_rank_updates_for_tier(tier, destination_with_target);
        if source_tier != "" and source_tier != tier {
            source_without_target = tier_recipes_sorted(source_tier, recipe_id);
            rank_updates = rank_updates.concat(
                build_rank_updates_for_tier(source_tier, source_without_target)
            );
        }

        previous_recipes = recipes.slice();
        loading = true;
        status_text = "Saving ranking placement...";
        try {
            result = root spawn SaveRecipeRankingBatch(updates=rank_updates);
            out = first_report_payload(result);
            if not out or out.updated == false {
                recipes = previous_recipes;
                err_text = String((out.error if out else "Recipe ranking failed."));
                status_text = "Ranking save failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }
            confirmed_updates = (out.updates if out and is_listish(out.updates) else rank_updates);
            recipes = apply_rank_updates(previous_recipes, confirmed_updates);
            await load_recipe_history_api(True);
            clear_ranking_session();
            if pending_rate_recipe_id == recipe_id {
                pending_rate_recipe_id = "";
            }
            status_text = ["Ranked recipe in ", tier_label(tier), "."].join("");
        } except Exception as e {
            recipes = previous_recipes;
            err_text = e.toString();
            status_text = "Ranking save failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async def start_recipe_ranking(recipe_id: str, tier: str) -> None {
        recipe = recipe_by_id(recipe_id);
        if not recipe or Object.keys(recipe).length == 0 {
            status_text = "Recipe not found.";
            return;
        }

        candidates = tier_recipes_sorted(tier, recipe_id);
        clear_ranking_session();
        re_rank_recipe_id = recipe_id;
        if candidates.length == 0 {
            status_text = ["Saving ranking placement in ", tier_label(tier), "."].join("");
            await finalize_recipe_ranking(recipe_id, tier, 0);
            return;
        }

        next_low = 0;
        next_high = candidates.length - 1;
        next_mid = Math.floor((next_low + next_high) / 2);
        compare_recipe = rank_comparison_from(candidates, next_mid);
        active_rank_recipe_id = recipe_id;
        active_rank_tier = tier;
        active_rank_candidates = candidates;
        active_rank_low = next_low;
        active_rank_high = next_high;
        active_rank_mid = next_mid;
        status_text = ["Compare against ", String(compare_recipe.title or "the middle recipe"), " to place this recipe in ", tier_label(tier), "."].join("");
    }

    async def handle_rank_tier_click(e: any) -> None {
        recipe_id = event_attr(e, "data-recipe-key").trim();
        tier = event_attr(e, "data-tier").trim().toLowerCase();
        if recipe_id == "" or tier == "" {
            status_text = "Recipe ranking data is missing.";
            return;
        }
        await start_recipe_ranking(recipe_id, tier);
    }

    async def submit_rank_choice(current_recipe_wins: bool) -> None {
        if active_rank_recipe_id == "" or active_rank_tier == "" {
            status_text = "Choose a tier before comparing recipes.";
            return;
        }

        next_low = active_rank_low;
        next_high = active_rank_high;
        if current_recipe_wins {
            next_high = active_rank_mid - 1;
        } else {
            next_low = active_rank_mid + 1;
        }

        if next_low > next_high {
            status_text = ["Saving ranking placement in ", tier_label(active_rank_tier), "."].join("");
            await finalize_recipe_ranking(active_rank_recipe_id, active_rank_tier, next_low);
            return;
        }

        next_mid = Math.floor((next_low + next_high) / 2);
        compare_recipe = rank_comparison_from(active_rank_candidates, next_mid);
        active_rank_low = next_low;
        active_rank_high = next_high;
        active_rank_mid = next_mid;
        status_text = ["Next comparison: ", String(compare_recipe.title or "recipe"), "."].join("");
    }

    async def handle_rank_compare_click(e: any) -> None {
        outcome = event_attr(e, "data-current-wins").trim().toLowerCase();
        await submit_rank_choice(outcome == "true");
    }

    async def delete_saved_recipe(recipe_id: str) -> None {
        recipe = recipe_by_id(recipe_id);
        if not recipe or Object.keys(recipe).length == 0 {
            status_text = "Recipe not found.";
            return;
        }

        loading = true;
        status_text = "Deleting saved recipe...";
        clear_ranking_session();
        if pending_rate_recipe_id == recipe_id {
            pending_rate_recipe_id = "";
        }
        remove_recipe_from_list(recipe_id);
        try {
            result = root spawn DeleteSavedRecipe(recipe_id=recipe_id);
            out = first_report_payload(result);
            if out and out.deleted == false {
                err_text = String(out.error or "Recipe delete failed.");
                replace_recipe_in_list(recipe);
                status_text = "Delete failed: " + err_text;
                maybe_trigger_auth_error(err_text);
                loading = false;
                return;
            }
            if String(generated_recipe.recipe_id or "") == recipe_id {
                generated_recipe = {};
            }
            status_text = "Saved recipe deleted.";
        } except Exception as e {
            replace_recipe_in_list(recipe);
            err_text = e.toString();
            status_text = "Delete failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async def handle_saved_recipe_delete_click(e: any) -> None {
        recipe_id = event_attr(e, "data-recipe-id").trim();
        if recipe_id == "" {
            return;
        }
        await delete_saved_recipe(recipe_id);
    }

    def toggle_saved_recipe_details(recipe_id: str) -> None {
        if recipe_id == "" {
            return;
        }
        if expanded_recipe_id == recipe_id {
            expanded_recipe_id = "";
        } else {
            expanded_recipe_id = recipe_id;
        }
    }

    async def handle_saved_recipe_title_click(e: any) -> None {
        recipe_id = event_attr(e, "data-recipe-id").trim();
        toggle_saved_recipe_details(recipe_id);
    }

    async def make_saved_recipe_again(recipe_id: str) -> None {
        recipe = recipe_by_id(recipe_id);
        if not recipe or Object.keys(recipe).length == 0 {
            status_text = "Recipe not found.";
            return;
        }
        if clone_recipe_ingredients(recipe.ingredients).length == 0 {
            status_text = "This saved recipe does not have stored ingredient data yet.";
            return;
        }
        expanded_recipe_id = recipe_id;
        await complete_recipe_and_update_pantry(clone_recipe(recipe));
    }

    async def handle_saved_recipe_make_click(e: any) -> None {
        recipe_id = event_attr(e, "data-recipe-id").trim();
        if recipe_id == "" {
            return;
        }
        await make_saved_recipe_again(recipe_id);
    }

    async def load_saved_recipe_api() -> None {
        loading = true;
        status_text = "Loading saved recipe...";
        try {
            result = root spawn ListGeneratedRecipe();
            out = first_report_payload(result);
            if out and out.recipe_name and String(out.recipe_name).trim().length > 0 {
                generated_recipe = out;
                show_made_confirm = false;
                await load_saved_macro_needs();
                status_text = "Loaded saved recipe from backend.";
            } else {
                generated_recipe = {};
                show_made_confirm = false;
                status_text = "No saved recipe found.";
            }
        } except Exception as e {
            err_text = e.toString();
            status_text = "Load failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async def clear_saved_recipe_api() -> None {
        loading = true;
        status_text = "Clearing recipe...";
        try {
            root spawn ClearGeneratedRecipe();
            generated_recipe = {};
            show_made_confirm = false;
            status_text = "Saved recipe cleared.";
        } except Exception as e {
            err_text = e.toString();
            status_text = "Clear failed: " + err_text;
            maybe_trigger_auth_error(err_text);
        }
        loading = false;
    }

    async can with entry {
        await load_saved_recipe_api();
        await load_recipe_history_api(True);
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

            <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(320px, 1fr))", "gap": "12px"}}>
                <div style={{"border": "1px solid #e2e8f0", "borderRadius": "12px", "padding": "12px", "background": "#fcfdff", "display": "grid", "gap": "10px"}}>
                    <h3 style={{"margin": "0"}}>Pantry Inputs For Recipe API</h3>
                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(110px, 1fr))", "gap": "8px", "alignItems": "end"}}>
                        <input
                            value={pantry_name}
                            onChange={lambda e: any -> None { pantry_name = e.target.value; }}
                            placeholder="name"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px", "gridColumn": "span 2"}}
                        />
                        <input
                            value={pantry_quantity}
                            onChange={lambda e: any -> None { pantry_quantity = e.target.value; }}
                            placeholder="qty"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        />
                        <select
                            value={pantry_unit}
                            onChange={lambda e: any -> None { pantry_unit = e.target.value; }}
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        >
                            <option value="PIECE">PIECE</option>
                            <option value="LB">LB</option>
                            <option value="OZ">OZ</option>
                            <option value="CUP">CUP</option>
                            <option value="TBSP">TBSP</option>
                            <option value="TSP">TSP</option>
                            <option value="CLOVE">CLOVE</option>
                            <option value="BUNCH">BUNCH</option>
                        </select>
                        <input
                            value={pantry_cost}
                            onChange={lambda e: any -> None { pantry_cost = e.target.value; }}
                            placeholder="cost/serv"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        />
                        <input
                            value={pantry_protein}
                            onChange={lambda e: any -> None { pantry_protein = e.target.value; }}
                            placeholder="protein/serv"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        />
                        <input
                            value={pantry_carb}
                            onChange={lambda e: any -> None { pantry_carb = e.target.value; }}
                            placeholder="carb/serv"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        />
                        <input
                            value={pantry_fat}
                            onChange={lambda e: any -> None { pantry_fat = e.target.value; }}
                            placeholder="fat/serv"
                            style={{"padding": "8px", "border": "1px solid #cbd5e1", "borderRadius": "8px"}}
                        />
                        <button
                            onClick={add_pantry_item}
                            style={{"padding": "8px", "borderRadius": "8px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "700"}}
                        >
                            Add
                        </button>
                    </div>

                    {(
                        <div style={{"opacity": "0.75"}}>No pantry items yet.</div>
                    ) if pantry_items_ref().length == 0 else (
                        <div style={{"overflowX": "auto"}}>
                            <table style={{"width": "100%", "borderCollapse": "collapse"}}>
                                <thead>
                                    <tr style={{"background": "#eff6ff"}}>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Name</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Total Qty</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Total Unit</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Serving Size</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Cost/Serv</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>P/Serv</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>C/Serv</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>F/Serv</th>
                                        <th style={{"textAlign": "left", "padding": "8px", "fontSize": "0.85rem"}}>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {pantry_items_ref().map(
                                        lambda item: dict -> JsxElement { return
                                            <tr key={item.name} style={{"borderTop": "1px solid #e2e8f0"}}>
                                                <td style={{"padding": "8px"}}>{item.name}</td>
                                                <td style={{"padding": "8px"}}>{total_quantity_value(item)}</td>
                                                <td style={{"padding": "8px"}}>{total_quantity_unit(item)}</td>
                                                <td style={{"padding": "8px"}}>{serving_size_display(item)}</td>
                                                <td style={{"padding": "8px"}}>{item.cost}</td>
                                                <td style={{"padding": "8px"}}>{item.protein}</td>
                                                <td style={{"padding": "8px"}}>{item.carb}</td>
                                                <td style={{"padding": "8px"}}>{item.fat}</td>
                                                <td style={{"padding": "8px"}}>
                                                    <button
                                                        data-item-name={String(item.name or "")}
                                                        onClick={handle_remove_pantry_item_click}
                                                        style={{"padding": "6px 8px", "borderRadius": "8px", "border": "1px solid #991b1b", "background": "#fee2e2"}}
                                                    >
                                                        Remove
                                                    </button>
                                                </td>
                                            </tr>; }
                                    )}
                                </tbody>
                            </table>
                        </div>
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
                    ) if (generated_recipe and generated_recipe.instructions and is_listish(generated_recipe.instructions) and generated_recipe.instructions.length > 0) else <div /> }
                    {(
                        <div style={{"display": "grid", "gap": "8px", "marginTop": "10px", "padding": "10px", "borderRadius": "12px", "border": "1px solid #dbeafe", "background": "#eff6ff"}}>
                            <div style={{"fontWeight": "800"}}>Made This Recipe?</div>
                            <div style={{"fontSize": "0.92rem", "lineHeight": "1.45"}}>
                                If yes, CaloReceipt will remove the used ingredients from your pantry, move the recipe into Past Recipes, and then ask you to rate it.
                            </div>
                            {(
                                <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                                    <span style={{"padding": "5px 10px", "borderRadius": "999px", "border": "1px solid #86efac", "background": "#dcfce7", "color": "#166534", "fontWeight": "800"}}>
                                        Added To Past Recipes
                                    </span>
                                    <span style={{"fontSize": "0.88rem", "opacity": "0.76"}}>
                                        Made: {format_made_time(generated_recipe_history_entry())}
                                    </span>
                                </div>
                            ) if generated_recipe_history_entry().made else (
                                <button onClick={lambda -> None { show_made_confirm = true; }} style={{"padding": "9px 12px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "800", "width": "fit-content"}}>
                                    Yes, I Made This Recipe
                                </button>
                            )}
                            {(
                                <div style={{"display": "grid", "gap": "8px", "padding": "10px", "borderRadius": "10px", "border": "1px solid #bfdbfe", "background": "#ffffff"}}>
                                    <div style={{"fontWeight": "800"}}>Confirm Recipe Completion</div>
                                    <div style={{"fontSize": "0.9rem", "lineHeight": "1.45"}}>
                                        Use this only after you actually made the recipe. We will subtract the listed ingredients from your pantry and send the recipe to Past Recipes.
                                    </div>
                                    <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                                        <button onClick={mark_generated_recipe_made} disabled={loading} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "800", "opacity": ("0.7" if loading else "1")}}>
                                            Yes, Update Pantry And Continue
                                        </button>
                                        <button onClick={lambda -> None { show_made_confirm = false; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff", "fontWeight": "700"}}>
                                            Not Yet
                                        </button>
                                    </div>
                                </div>
                            ) if show_made_confirm else None}
                        </div>
                    ) if Object.keys(generated_recipe).length > 0 else <div />}
                </div>

            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                <button onClick={lambda -> None { filter_mode = "all"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "all" else "#ffffff")}}>All</button>
                <button onClick={lambda -> None { filter_mode = "favorites"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "favorites" else "#ffffff")}}>Favorites</button>
                <button onClick={lambda -> None { filter_mode = "history"; }} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#dbeafe" if filter_mode == "history" else "#ffffff")}}>Past Recipes</button>
            </div>

            <div style={{"padding": "10px 12px", "border": "1px solid #dbeafe", "background": "#eff6ff", "borderRadius": "12px", "fontSize": "0.94rem", "lineHeight": "1.5"}}>
                Rank each recipe by picking a tier first, then compare it against the middle recipe in that tier until the binary-search flow finds its slot. Scores are recalculated on a `1.0-10.0` scale inside each tier.
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
                {(
                    <div style={{"opacity": "0.75"}}>No saved recipes yet.</div>
                ) if visible_recipes().length == 0 else (
                    visible_recipes().map(
                        lambda recipe: dict -> JsxElement { return
                            <div key={recipe_lookup_key(recipe)} style={{"border": ("2px solid #93c5fd" if pending_rate_recipe_id == String(recipe.recipe_id or "") else "1px solid #e2e8f0"), "borderRadius": "12px", "padding": "12px", "background": ("#f8fbff" if pending_rate_recipe_id == String(recipe.recipe_id or "") else "#fcfdff"), "display": "grid", "gap": "8px"}}>
                                <div style={{"display": "flex", "justifyContent": "space-between", "gap": "8px"}}>
                                    <button
                                        data-recipe-id={recipe_lookup_key(recipe)}
                                        onClick={handle_saved_recipe_title_click}
                                        style={{"margin": "0", "padding": "0", "border": "none", "background": "transparent", "fontSize": "1.05rem", "fontWeight": "800", "textAlign": "left", "color": "#1d4ed8", "textDecoration": "underline", "cursor": "pointer"}}
                                    >
                                        {recipe.title}
                                    </button>
                                    <div style={{"display": "flex", "gap": "6px", "alignItems": "center"}}>
                                        <button data-recipe-id={String(recipe.recipe_id or "")} onClick={handle_saved_recipe_favorite_click} style={{"border": "1px solid #fbcfe8", "background": "#fdf2f8", "borderRadius": "8px", "padding": "4px 8px"}}>
                                            {("★ Favorite" if recipe.favorite else "☆ Favorite")}
                                        </button>
                                        <button data-recipe-id={String(recipe.recipe_id or "")} onClick={handle_saved_recipe_delete_click} title="Delete saved recipe" style={{"border": "1px solid #fecaca", "background": "#fff1f2", "borderRadius": "8px", "padding": "4px 8px"}}>
                                            🗑
                                        </button>
                                    </div>
                                </div>
                                <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap", "fontSize": "0.9rem", "opacity": "0.78"}}>
                                    <span>Generated: {format_saved_time(recipe)}</span>
                                    <span>{("Hide Directions" if recipe_details_open(recipe) else "Show Directions")}</span>
                                    {(
                                        <span style={{"padding": "4px 9px", "borderRadius": "999px", "border": "1px solid #86efac", "background": "#dcfce7", "color": "#166534", "fontWeight": "800", "opacity": "1"}}>
                                            Past Recipe
                                        </span>
                                    ) if recipe.made else None}
                                    {(
                                        <span>Made: {format_made_time(recipe)}</span>
                                    ) if recipe.made else None}
                                </div>
                                {(
                                    <div style={{"display": "grid", "gap": "10px", "padding": "12px", "border": "1px solid #bfdbfe", "borderRadius": "12px", "background": "#eff6ff"}}>
                                        <div style={{"display": "flex", "justifyContent": "space-between", "gap": "10px", "alignItems": "center", "flexWrap": "wrap"}}>
                                            <div style={{"fontWeight": "800"}}>Directions</div>
                                            <button
                                                data-recipe-id={recipe_lookup_key(recipe)}
                                                onClick={handle_saved_recipe_make_click}
                                                disabled={loading}
                                                style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#dcfce7", "fontWeight": "800", "opacity": ("0.7" if loading else "1")}}
                                            >
                                                {("Make Again And Update Pantry" if recipe.made else "Make Recipe And Update Pantry")}
                                            </button>
                                        </div>
                                        {(
                                            <ol style={{"margin": "0", "paddingLeft": "20px", "display": "grid", "gap": "6px"}}>
                                                {recipe.instructions.map(
                                                    lambda step: str -> JsxElement { return <li key={step}>{step}</li>; }
                                                )}
                                            </ol>
                                        ) if (recipe.instructions and is_listish(recipe.instructions) and recipe.instructions.length > 0) else (
                                            <div style={{"fontSize": "0.92rem", "opacity": "0.78"}}>
                                                No saved directions are available for this recipe yet.
                                            </div>
                                        )}
                                        {(
                                            <div style={{"display": "grid", "gap": "6px"}}>
                                                <div style={{"fontWeight": "800"}}>Ingredients</div>
                                                <div style={{"display": "grid", "gap": "6px"}}>
                                                    {recipe.ingredients.map(
                                                        lambda item: dict -> JsxElement { return
                                                            <div key={[item.name, item.quantity, item.unit].join("-")} style={{"display": "flex", "justifyContent": "space-between", "gap": "8px", "padding": "8px 10px", "border": "1px solid #dbeafe", "borderRadius": "10px", "background": "#ffffff"}}>
                                                                <span>{item.name}</span>
                                                                <span>{[String(item.quantity or 0), " ", norm_unit(item.unit)].join("")}</span>
                                                            </div>; }
                                                    )}
                                                </div>
                                            </div>
                                        ) if (recipe.ingredients and is_listish(recipe.ingredients) and recipe.ingredients.length > 0) else None}
                                    </div>
                                ) if recipe_details_open(recipe) else None}
                                {(
                                    <div style={{"padding": "9px 10px", "borderRadius": "10px", "border": "1px solid #bfdbfe", "background": "#eff6ff", "fontWeight": "700"}}>
                                        You made this recipe. Choose a tier now to rate it.
                                    </div>
                                ) if pending_rate_recipe_id == String(recipe.recipe_id or "") else None}
                                <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                                    <span style={rating_badge_style(recipe)}>{rating_display_text(recipe)}</span>
                                    <span style={tier_chip_style(recipe_tier(recipe))}>{tier_label(recipe_tier(recipe))}</span>
                                    {(
                                        <span style={{"fontSize": "0.85rem", "opacity": "0.72"}}>
                                            Slot #{String(rating_order_value(recipe) + 1)}
                                        </span>
                                    ) if rating_order_value(recipe) >= 0 else None}
                                </div>
                                <div style={{"display": "grid", "gap": "8px", "padding": "10px", "border": "1px solid #e2e8f0", "borderRadius": "10px", "background": "#f8fafc"}}>
                                    <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "8px", "flexWrap": "wrap"}}>
                                        <div style={{"fontWeight": "800"}}>
                                            {("Rate This Recipe" if recipe_tier(recipe) == "" else "Recipe Ranked")}
                                        </div>
                                        {(
                                            <button onClick={lambda -> None { re_rank_recipe_id = recipe_lookup_key(recipe); }} style={{"padding": "7px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff", "fontWeight": "700"}}>
                                                Change Ranking
                                            </button>
                                        ) if recipe_tier(recipe) != "" and not show_rank_controls(recipe) else None}
                                    </div>
                                    {(
                                        <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                                            <button
                                                data-recipe-key={recipe_lookup_key(recipe)}
                                                data-tier="very_good"
                                                onClick={handle_rank_tier_click}
                                                style={tier_button_style("very_good", active_rank_recipe_id == recipe_lookup_key(recipe) and active_rank_tier == "very_good")}
                                            >
                                                Very Good
                                            </button>
                                            <button
                                                data-recipe-key={recipe_lookup_key(recipe)}
                                                data-tier="average"
                                                onClick={handle_rank_tier_click}
                                                style={tier_button_style("average", active_rank_recipe_id == recipe_lookup_key(recipe) and active_rank_tier == "average")}
                                            >
                                                Average
                                            </button>
                                            <button
                                                data-recipe-key={recipe_lookup_key(recipe)}
                                                data-tier="not_great"
                                                onClick={handle_rank_tier_click}
                                                style={tier_button_style("not_great", active_rank_recipe_id == recipe_lookup_key(recipe) and active_rank_tier == "not_great")}
                                            >
                                                Not Great
                                            </button>
                                        </div>
                                    ) if show_rank_controls(recipe) else (
                                        <div style={{"fontSize": "0.9rem", "opacity": "0.78"}}>
                                            Ranking saved. The score badge above is the current placement for this recipe.
                                        </div>
                                    )}
                                    {(
                                        <div style={{"display": "grid", "gap": "8px", "padding": "10px", "borderRadius": "10px", "border": "1px solid #bfdbfe", "background": "#eff6ff"}}>
                                            <div style={{"fontWeight": "800"}}>Binary Placement: {tier_label(active_rank_tier)}</div>
                                            <div style={{"fontSize": "0.92rem", "lineHeight": "1.45"}}>
                                                Compare this recipe with the middle recipe in the selected tier. Each answer cuts the remaining search range down until the exact slot is found.
                                            </div>
                                            <div style={{"display": "grid", "gridTemplateColumns": "1fr auto 1fr", "gap": "8px", "alignItems": "center"}}>
                                                <div style={{"padding": "9px", "borderRadius": "10px", "border": "1px solid #86efac", "background": "#f0fdf4"}}>
                                                    <div style={{"fontWeight": "800"}}>{recipe.title}</div>
                                                    <div style={{"opacity": "0.74", "fontSize": "0.88rem"}}>New placement candidate</div>
                                                </div>
                                                <div style={{"fontWeight": "800", "opacity": "0.66"}}>vs</div>
                                                <div style={{"padding": "9px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff"}}>
                                                    <div style={{"fontWeight": "800"}}>{current_rank_comparison().title}</div>
                                                    <div style={{"opacity": "0.74", "fontSize": "0.88rem"}}>
                                                        Current score: {rating_display_text(current_rank_comparison())}
                                                    </div>
                                                </div>
                                            </div>
                                            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                                                <button data-current-wins="true" onClick={handle_rank_compare_click} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #15803d", "background": "#dcfce7", "fontWeight": "800"}}>
                                                    This Recipe Is Better
                                                </button>
                                                <button data-current-wins="false" onClick={handle_rank_compare_click} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #475569", "background": "#e2e8f0", "fontWeight": "800"}}>
                                                    {String(current_rank_comparison().title or "Compared Recipe")} Is Better
                                                </button>
                                                <button onClick={clear_ranking_session} style={{"padding": "8px 10px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": "#ffffff", "fontWeight": "700"}}>
                                                    Cancel
                                                </button>
                                            </div>
                                        </div>
                                    ) if active_rank_recipe_id == recipe_lookup_key(recipe) else None}
                                </div>
                                <div style={{"fontSize": "0.9rem"}}><b>Notes:</b> {recipe.notes}</div>
                            </div>; }
                    )
                )}
            </div>
        </div>;
}
