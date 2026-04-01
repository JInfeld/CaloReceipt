"""Ingredient module wiring.
Generate a recipe from a user profile and available pantry ingredients.
"""

import from llm_config {
    llm
}
import importlib;
import os;
import sys;
import time;
import uuid;

import from receipt {
    extract_receipt_text
}

import from user {
    user,
    user_from_dict
}

enum Unit { PIECE, LOAF, LB, OZ, CUP, TBSP, TSP, CLOVE, BUNCH }

# Pantry/recipe ingredient schema shared by frontend payloads and LLM output.
obj Ingredient {
    has name: str;
    has quantity: float;
    has unit: Unit;
    has cost: float;
    has protein: float;
    has carb: float;
    has fat: float;
    has serving_size: str = "";
    has package_quantity: float = 0.0;
    has package_unit: Unit = Unit.PIECE;
}

sem Ingredient.cost = "Estimated cost in USD. For stored pantry items this is one USDA serving.";
sem Ingredient.protein = "Estimated amount of protein in grams. For stored pantry items this is one USDA serving.";
sem Ingredient.carb = "Estimated amount of carbohydrate in grams. For stored pantry items this is one USDA serving.";
sem Ingredient.fat = "Estimated amount of fat in grams. For stored pantry items this is one USDA serving.";
sem Ingredient.serving_size = "Human-readable USDA serving size text when available (examples: 2 Tbsp, 1 egg, 1 slice).";
sem Ingredient.package_quantity = "Actual purchased or remaining package quantity for user-facing inventory display.";
sem Ingredient.package_unit = "Actual purchased or remaining package unit for user-facing inventory display.";

obj RecipePlan {
    has recipe_name: str;
    has instructions: list[str];
    has recipe_ingredients: list[Ingredient];
    has total_calories: float;
    has total_protein_g: float;
    has total_carbs_g: float;
    has total_fat_g: float;
}

obj RankedRecipePlacement {
    has position: int;
    has title: str;
}

obj RankedRecipeScore {
    has position: int;
    has score: float;
}

obj RankedRecipeScoreBatch {
    has scores: list[RankedRecipeScore];
    has notes: str = "";
}

"""Generate a recipe using the user's profile and pantry ingredients.
Pantry inputs use serving-based storage:
quantity is the number of available servings,
unit is the pantry serving unit,
and cost/protein/carb/fat describe one USDA serving given by serving_size when present.
For output recipe_ingredients, quantity should be the total number of units used in the recipe.
"""
def generate_recipe(profile: user, pantry_ingredients: list[Ingredient]) -> RecipePlan by llm();

"""Assign relative 1.0-10.0 scores to an ordered recipe tier.
Input recipes are ordered best-to-worst inside exactly one named tier.
Return exactly one score for each input position using one decimal place.
Use only these ranges: very_good 7.0-10.0, average 4.0-6.9, not_great 1.0-3.9.
Position 0 must receive the highest score and later positions must never increase.
Spread scores meaningfully across the tier instead of bunching them together.
"""
def score_ranked_recipe_tier(
    tier_name: str,
    ordered_recipes: list[RankedRecipePlacement]
) -> RankedRecipeScoreBatch by llm();

obj IndexedPantryIngredient {
    has pantry_index: int;
    has name: str;
    has quantity: float;
    has unit: Unit;
    has cost: float;
    has protein: float;
    has carb: float;
    has fat: float;
}

obj PantryUsage {
    has pantry_index: int;
    has quantity_used: float;
    has reason: str = "";
}

obj PantryUsagePlan {
    has uses: list[PantryUsage];
    has notes: str = "";
}

obj CanonicalPantryBatch {
    has items: list[Ingredient];
    has notes: str = "";
}

"""Normalize pantry inventory into recipe-friendly serving units.
Keep the same products and preserve per-serving USDA macros and serving_size exactly when present.
Convert pantry storage into serving-based units chosen from the Unit enum.
quantity must become the number of available servings, and unit must be the single serving unit.
Prefer eggs and other discrete produce as PIECE, garlic as CLOVE, herbs as BUNCH,
dry goods like rice/oats/flour as CUP when a serving basis is clear,
and condiments/liquids like soy sauce or oil as CUP/TBSP/TSP when practical.
Do not invent products or negative values.
"""
def canonicalize_pantry_items_for_storage(items: list[Ingredient]) -> CanonicalPantryBatch by llm();

"""Plan how a cooked recipe should consume pantry inventory.
Use the provided pantry_index values to reference pantry items.
Return quantity_used in the SAME unit as the matched pantry item.
Match semantically similar foods and use common kitchen conversions when obvious
(examples: eggs by piece, rice by cup, soy sauce by cup/tbsp/tsp, garlic by clove).
Be conservative when uncertain. Never consume unrelated items and never exceed pantry quantity.
Multiple pantry items may be used to satisfy one recipe ingredient if needed.
"""
def plan_recipe_pantry_subtraction(
    pantry_items: list[IndexedPantryIngredient],
    recipe_ingredients: list[Ingredient]
) -> PantryUsagePlan by llm();

obj ReceiptPantryParse {
    has store_name: str;
    has subtotal: float;
    has tax: float;
    has extracted_text: str;
    has food_line_items: list[Ingredient];
    has receipt_total: float;
    has notes: str;
}

sem ReceiptPantryParse.store_name = "Exact store/merchant name as printed on receipt header; empty string if unreadable.";
sem ReceiptPantryParse.subtotal = "Receipt subtotal before tax/fees; 0 if not visible.";
sem ReceiptPantryParse.tax = "Tax amount; 0 if not visible.";
sem ReceiptPantryParse.extracted_text = "Raw text transcription of the visible receipt (line-by-line) before structured parsing.";
sem ReceiptPantryParse.food_line_items = "Only visible food line-items from the receipt. No inferred or invented products.";
sem ReceiptPantryParse.receipt_total = "Exact final total printed on the receipt (after discounts/tax) as a numeric USD value.";
sem ReceiptPantryParse.notes = "Short extraction notes; mention ambiguity and any excluded non-food lines.";

obj UsdaFoodSearchHint {
    has original_name: str;
    has search_name: str;
    has brand_name: str = "";
    has food_name: str = "";
    has preferred_data_types: list[str] = [];
    has alternate_names: list[str] = [];
    has notes: str = "";
}

obj UsdaFoodSearchPlan {
    has hints: list[UsdaFoodSearchHint];
    has notes: str = "";
}

obj UsdaMacroEstimate {
    has original_name: str;
    has protein: float;
    has carb: float;
    has fat: float;
    has notes: str = "";
}

obj UsdaMacroEstimateBatch {
    has items: list[UsdaMacroEstimate];
    has notes: str = "";
}

"""Parse a receipt image into pantry ingredients.
The input is a data URL string (e.g. data:image/jpeg;base64,...).
Keep exact product naming from the receipt (brand + product), e.g. "Great Value Chicken Breast".
Return one ingredient per visible food line only. Do NOT invent items that are not present.
Prefer exact label text from line item, including brand/store product prefixes.
If the item appears to be a store-brand product but the brand prefix is abbreviated or implied by the merchant, expand it into the likely house brand name when strongly supported by the store context.
Use line-item price as Ingredient.cost.
Before USDA lookup, quantity/unit must represent the FULL purchased item size or package amount,
not the USDA serving count. Examples: "Great Value Peanut Butter 16 oz" -> quantity=16, unit=OZ;
"Eggland's Best Eggs 12 ct" -> quantity=12, unit=PIECE.
If size is not printed directly but is strongly inferable from the item/store context, infer a conservative full-item quantity/unit.
Skip non-food lines and keep units inside the supported Unit enum.
Prefer full-item kitchen/package units when visible or strongly inferable
(examples: eggs as PIECE count, garlic as CLOVE count, herbs as BUNCH count, rice as OZ/LB/CUP package size, sauces/oils as OZ/CUP/TBSP/TSP bottle size).
If a line is uncertain or unreadable, exclude it rather than guessing.
Correct obvious OCR spelling mistakes in product names (example: "BU7TR" -> "BUTTER", "CHKN" -> "CHICKEN").
Expand receipt abbreviations/lingo into fully spelled item names while preserving brand when visible
(examples: "GV" -> "Great Value", "PNT BUTTR" -> "Peanut Butter", "PARM" -> "Parmesan", "CHNK CHKN" -> "Chunk Chicken").
Prefer clear consumer-facing pantry names over cryptic receipt shorthand.
Do not hallucinate missing words: only expand abbreviations when strongly supported by OCR context.
Extract store_name, subtotal, tax, and receipt_total exactly from visible printed text.
Ensure the sum of returned food_line_items costs closely matches receipt_total.
Always populate extracted_text with the full readable receipt transcription.
"""
def parse_receipt_image_into_pantry_items(receipt_image_data_url: str) -> ReceiptPantryParse by llm();

"""Parse EasyOCR receipt text into pantry ingredients.
Input text should be the OCR transcription from the receipt image.
Only extract food line-items that appear in the provided text; do not invent missing lines.
Treat each OCR line as evidence. Use product text and nearby price tokens on the same/adjacent line.
Preserve exact brand/product wording from OCR when possible.
If the item appears to be a store-brand product but the brand prefix is abbreviated or implied by the merchant, expand it into the likely house brand name when strongly supported by the store context.
Correct obvious OCR character/substitution errors in names when confidence is high from nearby tokens
(examples: 7->T in "BU7TR", 0->O in words, dropped vowels in common food words).
Translate receipt shorthand into fully spelled pantry names while keeping visible brand prefixes
(examples: "GV PNT BUTTR" -> "Great Value Peanut Butter", "GV CHNK CHKN" -> "Great Value Chunk Chicken").
If both an abbreviated and a clearer line for the same UPC/item exist, use the clearer fully spelled version.
Keep output names human-readable and standardized for pantry use, not raw receipt code strings.
quantity/unit must represent the FULL purchased item size or package amount before USDA serving conversion,
not the USDA serving count. If the amount is embedded in the item name, extract it into quantity/unit.
If size is not printed directly but is strongly inferable from the item/store context, infer a conservative full-item quantity/unit.
Prefer full-item kitchen/package units when the amount is visible or strongly inferable
(examples: eggs as PIECE count, garlic as CLOVE count, herbs as BUNCH count, rice as OZ/LB/CUP package size, sauces/oils as OZ/CUP/TBSP/TSP bottle size).
Ignore totals/subtotals/tax/payment lines as ingredients.
If OCR text is empty or unreadable, return empty food_line_items, receipt_total=0, and explain in notes.
"""
def parse_receipt_text_into_pantry_items(receipt_text: str) -> ReceiptPantryParse by llm();

"""Rewrite unresolved pantry item names into USDA FoodData Central style search hints.
Return exactly one hint per input item and copy original_name exactly.
Use only these preferred_data_types values: branded_food, foundation_food,
sr_legacy_food, survey_fndds_food.
Separate visible brand_name from food_name when possible.
If no item brand is visible, keep brand_name empty and use store_name only as a store-brand search alias when helpful.
search_name should be the best single USDA-style lookup phrase, usually brand + food_name when the brand is visible.
alternate_names may include de-branded or generic aliases and store-brand aliases derived from store_name.
Do not invent brands that are not present on the item itself.
"""
def build_usda_food_search_plan(
    items: list[Ingredient],
    store_name: str = ""
) -> UsdaFoodSearchPlan by llm();

"""Estimate pantry item macros using USDA FoodData Central conventions only.
Return exactly one result per input item and copy original_name exactly.
Protein/carb/fat must be for the FULL provided quantity/unit, not per 100 g.
Use the closest USDA FoodData Central equivalent you can infer.
If package size is unclear, make a conservative estimate and explain the assumption in notes.
Do not return negative values.
"""
def estimate_missing_item_macros_from_usda(items: list[Ingredient]) -> UsdaMacroEstimateBatch by llm();

def unit_from_any(raw_unit: any) -> Unit {
    unit_text = str(raw_unit).upper();
    if unit_text == "LOAF" {
        return Unit.LOAF;
    } elif unit_text == "LB" {
        return Unit.LB;
    } elif unit_text == "OZ" {
        return Unit.OZ;
    } elif unit_text == "CUP" {
        return Unit.CUP;
    } elif unit_text == "TBSP" {
        return Unit.TBSP;
    } elif unit_text == "TSP" {
        return Unit.TSP;
    } elif unit_text == "CLOVE" {
        return Unit.CLOVE;
    } elif unit_text == "BUNCH" {
        return Unit.BUNCH;
    }
    return Unit.PIECE;
}

def ingredient_from_payload(row: dict) -> Ingredient {
    name_text = str(row.get("name", "")).strip();
    if name_text == "" {
        name_text = "Unknown Ingredient";
    }
    return Ingredient(
        name=name_text,
        quantity=float(row.get("quantity", 1.0)),
        unit=unit_from_any(row.get("unit", "PIECE")),
        cost=float(row.get("cost", 0.0)),
        protein=float(row.get("protein", 0.0)),
        carb=float(row.get("carb", 0.0)),
        fat=float(row.get("fat", 0.0)),
        serving_size=str(row.get("serving_size", "")).strip(),
        package_quantity=float(row.get("package_quantity", 0.0)),
        package_unit=unit_from_any(row.get("package_unit", "PIECE"))
    );
}

def ingredient_to_payload(ing: Ingredient) -> dict {
    package_quantity = ing.package_quantity;
    package_unit = ing.package_unit;
    if package_quantity <= 0.0 {
        package_quantity = ing.quantity;
        package_unit = ing.unit;
    }
    if package_quantity > 0.0 and _is_loaf_style_bread_name(ing.name) and package_unit == Unit.PIECE and package_quantity <= 4.0 {
        package_unit = Unit.LOAF;
    }
    return {
        "name": ing.name,
        "quantity": ing.quantity,
        "unit": str(ing.unit).split(".")[-1].upper(),
        "cost": ing.cost,
        "protein": ing.protein,
        "carb": ing.carb,
        "fat": ing.fat,
        "serving_size": ing.serving_size,
        "package_quantity": _round_two(package_quantity),
        "package_unit": str(package_unit).split(".")[-1].upper()
    };
}

def _ingredient_as_serving_storage(ing: Ingredient) -> Ingredient {
    stored_quantity = ing.quantity;
    if stored_quantity <= 0.0 {
        stored_quantity = 1.0;
    }
    return Ingredient(
        name=ing.name,
        quantity=_round_two(stored_quantity),
        unit=ing.unit,
        cost=_round_two(ing.cost),
        protein=_round_two(ing.protein),
        carb=_round_two(ing.carb),
        fat=_round_two(ing.fat),
        serving_size=ing.serving_size,
        package_quantity=_round_two(ing.package_quantity),
        package_unit=ing.package_unit
    );
}

def _is_bread_like_name(raw_name: str) -> bool {
    name = _norm_food_name(raw_name);
    if name == "" {
        return False;
    }
    tokens = name.split(" ");
    for token in tokens {
        if token in ["bread", "loaf", "bun", "buns", "roll", "rolls", "bagel", "bagels", "tortilla", "tortillas", "wrap", "wraps", "naan", "pita", "slice", "sliced", "muffin", "muffins"] {
            return True;
        }
    }
    return False;
}

def _is_loaf_style_bread_name(raw_name: str) -> bool {
    tokens = _food_name_tokens(raw_name);
    if tokens == [] {
        return False;
    }
    excluded = {
        "bagel",
        "bun",
        "croissant",
        "flatbread",
        "muffin",
        "naan",
        "pita",
        "roll",
        "tortilla",
        "wrap"
    };
    for token in tokens {
        if token in excluded {
            return False;
        }
    }
    for token in tokens {
        if token in ["baguette", "bread", "brioche", "ciabatta", "loaf", "rye", "sourdough"] {
            return True;
        }
    }
    return False;
}

def _apply_storage_unit_overrides(ing: Ingredient) -> Ingredient {
    if _is_bread_like_name(ing.name) and ing.unit != Unit.PIECE and ing.unit != Unit.OZ and ing.unit != Unit.LB {
        return Ingredient(
            name=ing.name,
            quantity=ing.quantity,
            unit=Unit.PIECE,
            cost=ing.cost,
            protein=ing.protein,
            carb=ing.carb,
            fat=ing.fat,
            serving_size=ing.serving_size,
            package_quantity=ing.package_quantity,
            package_unit=ing.package_unit
        );
    }
    return ing;
}

def _apply_storage_unit_overrides_batch(items: list[Ingredient]) -> list[Ingredient] {
    updated: list[Ingredient] = [];
    for ing in items {
        updated.append(_apply_storage_unit_overrides(ing));
    }
    return updated;
}

def _ingredients_as_serving_storage(items: list[Ingredient]) -> list[Ingredient] {
    converted: list[Ingredient] = [];
    for ing in items {
        converted.append(_ingredient_as_serving_storage(ing));
    }
    return converted;
}

def _round_two(value: float) -> float {
    return float(int((value * 100.0) + 0.5)) / 100.0;
}

def _note_merge(base_note: str, extra_note: str) -> str {
    base = str(base_note).strip();
    extra = str(extra_note).strip();
    if extra == "" {
        return base;
    }
    if base == "" {
        return extra;
    }
    return "{} | {}".format(base, extra);
}

def _norm_food_name(raw_text: str) -> str {
    clean = str(raw_text).strip().lower();
    normalized = "";
    for ch in clean {
        if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") {
            normalized += ch;
        } elif ch == " " or ch == "-" or ch == "_" or ch == "/" {
            normalized += " ";
        }
    }
    return " ".join(normalized.split());
}

def _singular_food_token(token: str) -> str {
    clean = str(token).strip().lower();
    if clean.endswith("ies") and len(clean) > 3 {
        return clean[:-3] + "y";
    }
    if clean.endswith("es") and len(clean) > 3 {
        return clean[:-2];
    }
    if clean.endswith("s") and len(clean) > 3 {
        return clean[:-1];
    }
    return clean;
}

def _food_name_tokens(raw_text: str) -> list[str] {
    tokens: list[str] = [];
    for token in _norm_food_name(raw_text).split(" ") {
        clean = _singular_food_token(token);
        if clean == "" {
            continue;
        }
        if clean in ["fresh", "organic", "whole", "plain", "raw", "boneless", "skinless", "low", "sodium", "reduced", "fat", "free", "light", "natural"] {
            continue;
        }
        tokens.append(clean);
    }
    return tokens;
}

def _food_name_match_score(left_name: str, right_name: str) -> float {
    left_norm = _norm_food_name(left_name);
    right_norm = _norm_food_name(right_name);
    if left_norm == "" or right_norm == "" {
        return 0.0;
    }
    if left_norm == right_norm {
        return 100.0;
    }
    if left_norm in right_norm or right_norm in left_norm {
        return 85.0;
    }

    left_tokens = _food_name_tokens(left_name);
    right_tokens = _food_name_tokens(right_name);
    if left_tokens == [] or right_tokens == [] {
        return 0.0;
    }

    shared_count = 0;
    for left_token in left_tokens {
        if left_token in right_tokens {
            shared_count += 1;
        }
    }
    if shared_count == 0 {
        return 0.0;
    }

    left_ratio = float(shared_count) / float(len(left_tokens));
    right_ratio = float(shared_count) / float(len(right_tokens));
    return (left_ratio * 60.0) + (right_ratio * 40.0);
}

def _unit_text(raw_unit: any) -> str {
    return str(raw_unit).split(".")[-1].upper().strip();
}

def _unit_group(unit_text: str) -> str {
    if unit_text == "LB" or unit_text == "OZ" {
        return "mass";
    }
    if unit_text == "CUP" or unit_text == "TBSP" or unit_text == "TSP" {
        return "volume";
    }
    return unit_text;
}

def _unit_factor(unit_text: str) -> float {
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
    if unit_text == "LOAF" {
        return 1.0;
    }
    return 0.0;
}

def _convert_quantity_between_units(quantity: float, from_unit_raw: any, to_unit_raw: any) -> float {
    from_unit = _unit_text(from_unit_raw);
    to_unit = _unit_text(to_unit_raw);
    if quantity < 0.0 {
        return -1.0;
    }
    if from_unit == to_unit {
        return quantity;
    }
    if _unit_group(from_unit) != _unit_group(to_unit) {
        return -1.0;
    }
    from_factor = _unit_factor(from_unit);
    to_factor = _unit_factor(to_unit);
    if from_factor <= 0.0 or to_factor <= 0.0 {
        return -1.0;
    }
    return (quantity * from_factor) / to_factor;
}

def _now_ms() -> int {
    return int(time.time() * 1000.0);
}

def _diag_payload(request_id: str, start_ms: int, ocr_ms: int = -1, llm_ms: int = -1) -> dict {
    return {
        "request_id": request_id,
        "ocr_ms": ocr_ms,
        "llm_ms": llm_ms,
        "total_ms": _now_ms() - start_ms
    };
}

def _history_rating(rec: any) -> float {
    try {
        return float(rec.rating);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_recipe_id(rec: any) -> str {
    try {
        return str(rec.recipe_id).strip();
    } except Exception as _e {
        return "";
    }
}

def _ensure_history_recipe_id(rec: any) -> str {
    recipe_id = _history_recipe_id(rec);
    if recipe_id != "" {
        return recipe_id;
    }
    try {
        recipe_id = str(uuid.uuid4());
        rec.recipe_id = recipe_id;
        return recipe_id;
    } except Exception as _e {
        return "";
    }
}

def _history_legacy_key(title: any, generated_at_ms: any) -> str {
    try {
        clean_title = str(title).strip().lower();
        stamp = int(generated_at_ms);
        return "legacy::{}::{}".format(str(stamp), clean_title);
    } except Exception as _e {
        return "";
    }
}

def _history_title(rec: any) -> str {
    try {
        title = str(rec.title).strip();
        if title != "" {
            return title;
        }
    } except Exception as _e {
        0;
    }
    try {
        return str(rec.name).strip();
    } except Exception as _e {
        return "";
    }
}

def _history_total_calories(rec: any) -> float {
    try {
        return float(rec.total_calories);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_protein_g(rec: any) -> float {
    try {
        return float(rec.total_protein_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_carbs_g(rec: any) -> float {
    try {
        return float(rec.total_carbs_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_fat_g(rec: any) -> float {
    try {
        return float(rec.total_fat_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_generated_at_ms(rec: any) -> int {
    try {
        return int(rec.generated_at_ms);
    } except Exception as _e {
        return 0;
    }
}

def _history_rating_tier(rec: any) -> str {
    try {
        return str(rec.rating_tier).strip().lower();
    } except Exception as _e {
        return "";
    }
}

def _history_rating_order(rec: any) -> int {
    try {
        return int(rec.rating_order);
    } except Exception as _e {
        return -1;
    }
}

def _history_favorite(rec: any) -> bool {
    try {
        return rec.favorite;
    } except Exception as _e {
        return False;
    }
}

def _history_made(rec: any) -> bool {
    try {
        return rec.made;
    } except Exception as _e {
        return False;
    }
}

def _history_made_at_ms(rec: any) -> int {
    try {
        return int(rec.made_at_ms);
    } except Exception as _e {
        return 0;
    }
}

def _history_notes(rec: any) -> str {
    try {
        return str(rec.notes);
    } except Exception as _e {
        return "Generated from your profile + pantry";
    }
}

def _history_instructions(rec: any) -> list {
    steps: list = [];
    try {
        for step in rec.instructions {
            step_text = str(step).strip();
            if step_text != "" {
                steps.append(step_text);
            }
        }
    } except Exception as _e {
        return [];
    }
    return steps;
}

def _history_ingredients(rec: any) -> list {
    rows: list = [];
    try {
        for row in rec.ingredients {
            rows.append({
                "name": str(row.get("name", "")).strip(),
                "quantity": float(row.get("quantity", 0.0)),
                "unit": str(row.get("unit", "")).strip(),
                "cost": float(row.get("cost", 0.0)),
                "protein": float(row.get("protein", 0.0)),
                "carb": float(row.get("carb", 0.0)),
                "fat": float(row.get("fat", 0.0)),
                "serving_size": str(row.get("serving_size", "")).strip(),
                "package_quantity": float(row.get("package_quantity", 0.0)),
                "package_unit": str(row.get("package_unit", "")).strip()
            });
        }
    } except Exception as _e {
        return [];
    }
    return rows;
}

def _tier_min_rating(tier: str) -> float {
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

def _tier_max_rating(tier: str) -> float {
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

def _clamp_rating(value: float, min_value: float, max_value: float) -> float {
    if value < min_value {
        return min_value;
    }
    if value > max_value {
        return max_value;
    }
    return value;
}

def _round_one(value: float) -> float {
    return float(int((value * 10.0) + 0.5)) / 10.0;
}

def _fallback_score_for_tier_position(tier: str, position: int, total: int) -> float {
    min_score = _tier_min_rating(tier);
    max_score = _tier_max_rating(tier);
    if total <= 0 {
        return 0.0;
    }
    if total == 1 {
        return _round_one((min_score + max_score) / 2.0);
    }
    step = (max_score - min_score) / float(total - 1);
    return _round_one(_clamp_rating(max_score - (float(position) * step), min_score, max_score));
}

def _scored_rank_updates_for_tier(tier: str, rows: list[dict]) -> list[dict] {
    total = len(rows);
    if total == 0 {
        return [];
    }

    placements: list[RankedRecipePlacement] = [];
    for idx=0 to idx<total by idx+=1 {
        row = rows[idx];
        placements.append(
            RankedRecipePlacement(
                position=idx,
                title=str(row.get("title", "")).strip()
            )
        );
    }

    score_map: dict = {};
    use_fallback = False;
    min_score = _tier_min_rating(tier);
    max_score = _tier_max_rating(tier);

    try {
        llm_scores = score_ranked_recipe_tier(
            tier_name=tier,
            ordered_recipes=placements
        );
        if len(llm_scores.scores) != total {
            use_fallback = True;
        } else {
            for item in llm_scores.scores {
                pos = int(item.position);
                if pos < 0 or pos >= total {
                    use_fallback = True;
                    break;
                }
                pos_key = str(pos);
                if score_map.get(pos_key, None) != None {
                    use_fallback = True;
                    break;
                }
                score_map[pos_key] = _round_one(
                    _clamp_rating(float(item.score), min_score, max_score)
                );
            }
        }
    } except Exception as _e {
        use_fallback = True;
    }

    if not use_fallback {
        previous_score = max_score + 1.0;
        for idx=0 to idx<total by idx+=1 {
            pos_key = str(idx);
            if score_map.get(pos_key, None) == None {
                use_fallback = True;
                break;
            }
            current_score = float(score_map[pos_key]);
            if current_score > previous_score {
                use_fallback = True;
                break;
            }
            previous_score = current_score;
        }
    }

    scored_updates: list = [];
    for idx=0 to idx<total by idx+=1 {
        row = rows[idx];
        score = (
            float(score_map[str(idx)])
            if (not use_fallback and score_map.get(str(idx), None) != None)
            else _fallback_score_for_tier_position(tier, idx, total)
        );
        scored_updates.append({
            "recipe_id": str(row.get("recipe_id", "")).strip(),
            "recipe_key": str(row.get("recipe_key", "")).strip(),
            "title": str(row.get("title", "")).strip(),
            "generated_at_ms": int(row.get("generated_at_ms", 0)),
            "rating": score,
            "rating_tier": tier,
            "rating_order": idx
        });
    }
    return scored_updates;
}

def _is_noise_receipt_line(line_up: str) -> bool {
    if line_up.strip() == "" {
        return True;
    }
    if "SUBTOTAL" in line_up or "TOTAL" in line_up or "TAX" in line_up or "DEBIT" in line_up {
        return True;
    }
    if "CHANGE DUE" in line_up or "ACCOUNT" in line_up or "PAYMENT" in line_up {
        return True;
    }
    if "REF #" in line_up or "NETWORK ID" in line_up or "APPR CODE" in line_up {
        return True;
    }
    if "ST#" in line_up or "TR#" in line_up or "OP#" in line_up {
        return True;
    }
    return False;
}

def _looks_like_upc_or_code(line_up: str) -> bool {
    compact = line_up.replace(" ", "");
    digit_count = 0;
    alpha_count = 0;
    for ch in compact {
        if ch >= "0" and ch <= "9" {
            digit_count += 1;
        } elif ch >= "A" and ch <= "Z" {
            alpha_count += 1;
        }
    }
    if digit_count >= 10 and alpha_count <= 3 {
        return True;
    }
    return False;
}

def _extract_price_from_line(line_up: str) -> float {
    best = -1.0;
    for tok in line_up.split(" ") {
        t = tok.strip().replace("$", "");
        if t == "" {
            continue;
        }
        if t.find(".") < 0 {
            continue;
        }
        try {
            v = float(t);
            if v >= 0 and v <= 200 {
                best = v;
            }
        } except Exception as _e {
            0;
        }
    }
    return best;
}

def _normalize_receipt_name(line_up: str) -> str {
    x = line_up;
    x = x.replace("BU7TR", "BUTTER");
    x = x.replace("BUTTR", "BUTTER");
    x = x.replace("CHNK", "CHUNK");
    x = x.replace("CHKN", "CHICKEN");
    x = x.replace("PNT", "PEANUT");
    x = x.replace("PARM", "PARMESAN");
    x = x.replace("GV ", "GREAT VALUE ");
    x = x.replace("  ", " ").strip();
    if x == "" {
        return "";
    }
    return x;
}

def _clean_inline_qty_token(token_in: str) -> str {
    token = str(token_in).strip();
    while token != "" {
        last_ch = token[len(token) - 1];
        if last_ch == "," or last_ch == "." or last_ch == ")" or last_ch == "]" or last_ch == ";" or last_ch == ":" {
            token = token[:-1].strip();
        } else {
            break;
        }
    }
    while token != "" {
        first_ch = token[0];
        if first_ch == "(" or first_ch == "[" {
            token = token[1:].strip();
        } else {
            break;
        }
    }
    return token;
}

def _inline_numeric_value(token_in: str) -> float {
    token = _clean_inline_qty_token(token_in);
    if token == "" {
        return -1.0;
    }
    dot_count = 0;
    has_digit = False;
    for ch in token {
        if ch >= "0" and ch <= "9" {
            has_digit = True;
        } elif ch == "." {
            dot_count += 1;
            if dot_count > 1 {
                return -1.0;
            }
        } else {
            return -1.0;
        }
    }
    if not has_digit {
        return -1.0;
    }
    try {
        return float(token);
    } except Exception as _e {
        return -1.0;
    }
}

def _inline_receipt_unit(token_in: str) -> str {
    token = _clean_inline_qty_token(token_in).lower();
    if token == "oz" or token == "ounce" or token == "ounces" {
        return "OZ";
    }
    if token == "lb" or token == "lbs" or token == "pound" or token == "pounds" {
        return "LB";
    }
    if token == "cup" or token == "cups" {
        return "CUP";
    }
    if token == "tbsp" or token == "tablespoon" or token == "tablespoons" {
        return "TBSP";
    }
    if token == "tsp" or token == "teaspoon" or token == "teaspoons" {
        return "TSP";
    }
    if token == "clove" or token == "cloves" {
        return "CLOVE";
    }
    if token == "bunch" or token == "bunches" {
        return "BUNCH";
    }
    if token == "ct" or token == "count" or token == "counts" or token == "pk" or token == "pack" or token == "packs" {
        return "PIECE";
    }
    return "";
}

def _trim_inline_amount_from_name(raw_name: str) -> dict {
    clean_name = str(raw_name).strip();
    if clean_name == "" {
        return {"matched": False, "name": "", "quantity": 0.0, "unit": ""};
    }

    tokens: list[str] = [];
    for token in clean_name.split(" ") {
        piece = str(token).strip();
        if piece != "" {
            tokens.append(piece);
        }
    }
    if len(tokens) < 2 {
        return {"matched": False, "name": clean_name, "quantity": 0.0, "unit": ""};
    }

    matched_len = 0;
    amount = -1.0;
    unit_text = "";

    last_token = _clean_inline_qty_token(tokens[len(tokens) - 1]).lower();
    prev_token = _clean_inline_qty_token(tokens[len(tokens) - 2]).lower();

    if len(tokens) >= 3 and last_token == "oz" and prev_token == "fl" {
        amount = _inline_numeric_value(tokens[len(tokens) - 3]);
        if amount > 0.0 {
            matched_len = 3;
            unit_text = "CUP";
            amount = amount / 8.0;
        }
    }

    if matched_len == 0 {
        unit_text = _inline_receipt_unit(tokens[len(tokens) - 1]);
        amount = _inline_numeric_value(tokens[len(tokens) - 2]);
        if unit_text != "" and amount > 0.0 {
            matched_len = 2;
        }
    }

    if matched_len == 0 {
        return {"matched": False, "name": clean_name, "quantity": 0.0, "unit": ""};
    }

    next_name = " ".join(tokens[:-matched_len]).strip();
    while next_name != "" {
        last_ch = next_name[len(next_name) - 1];
        if last_ch == " " or last_ch == "," or last_ch == "-" or last_ch == ":" or last_ch == ";" or last_ch == "/" {
            next_name = next_name[:-1].strip();
        } else {
            break;
        }
    }
    if next_name == "" {
        return {"matched": False, "name": clean_name, "quantity": 0.0, "unit": ""};
    }
    return {
        "matched": True,
        "name": next_name,
        "quantity": amount,
        "unit": unit_text
    };
}

def _ingredient_with_inline_amount(ing: Ingredient) -> Ingredient {
    extracted = _trim_inline_amount_from_name(ing.name);
    if not extracted.get("matched", False) {
        return ing;
    }

    next_name = str(extracted.get("name", "")).strip();
    if next_name == "" {
        next_name = ing.name;
    }

    next_quantity = ing.quantity;
    next_unit = ing.unit;
    inline_quantity = float(extracted.get("quantity", 0.0));
    inline_unit_text = str(extracted.get("unit", "")).strip();
    if inline_quantity > 0.0 and inline_unit_text != "" and ing.unit == Unit.PIECE {
        piece_count = ing.quantity;
        if piece_count <= 0.0 {
            piece_count = 1.0;
        }
        next_quantity = inline_quantity * piece_count;
        next_unit = unit_from_any(inline_unit_text);
    }

    return Ingredient(
        name=next_name,
        quantity=_round_two(next_quantity),
        unit=next_unit,
        cost=ing.cost,
        protein=ing.protein,
        carb=ing.carb,
        fat=ing.fat,
        serving_size=ing.serving_size,
        package_quantity=(
            ing.package_quantity
            if ing.package_quantity > 0.0
            else _round_two(next_quantity)
        ),
        package_unit=(
            ing.package_unit
            if ing.package_quantity > 0.0
            else next_unit
        )
    );
}

def _apply_inline_amount_cleanup(items: list[Ingredient], context_label: str) -> list[Ingredient] {
    cleaned: list[Ingredient] = [];
    for ing in items {
        updated = _ingredient_with_inline_amount(ing);
        if updated.name != ing.name or updated.quantity != ing.quantity or updated.unit != ing.unit {
            print(
                "[ReceiptInlineAmount] context={} from_name='{}' to_name='{}' quantity={} unit={}".format(
                    context_label,
                    ing.name,
                    updated.name,
                    str(updated.quantity),
                    _unit_text(updated.unit)
                )
            );
        }
        cleaned.append(updated);
    }
    return cleaned;
}

def _fallback_extract_items_from_ocr_text(text_in: str) -> list {
    items: list = [];
    pending_name = "";
    for raw in text_in.split("\n") {
        line_up = str(raw).strip().upper();
        if _is_noise_receipt_line(line_up) {
            continue;
        }

        price = _extract_price_from_line(line_up);
        if not _looks_like_upc_or_code(line_up) {
            normalized_name = _normalize_receipt_name(line_up);
            # Keep only lines that contain at least one alphabetic character.
            has_alpha = False;
            for ch in normalized_name {
                if ch >= "A" and ch <= "Z" {
                    has_alpha = True;
                    break;
                }
            }
            if has_alpha {
                pending_name = normalized_name;
            }
        }

        if price >= 0 and pending_name != "" {
            items.append({
                "name": pending_name,
                "quantity": 1.0,
                "unit": "PIECE",
                "cost": price,
                "protein": 0.0,
                "carb": 0.0,
                "fat": 0.0
            });
            pending_name = "";
        }
    }
    return items;
}

def _restore_source_inventory_fields(normalized_items: list[Ingredient], source_items: list[Ingredient]) -> list[Ingredient] {
    if normalized_items == [] or source_items == [] {
        return source_items;
    }
    if len(normalized_items) != len(source_items) {
        return source_items;
    }

    restored: list[Ingredient] = [];
    idx = 0;
    for normalized in normalized_items {
        source = source_items[idx];
        next_name = str(normalized.name).strip();
        if next_name == "" {
            next_name = source.name;
        }
        restored.append(
            Ingredient(
                name=next_name,
                quantity=source.quantity,
                unit=source.unit,
                cost=source.cost,
                protein=source.protein,
                carb=source.carb,
                fat=source.fat,
                serving_size=(
                    source.serving_size
                    if str(source.serving_size).strip() != ""
                    else str(normalized.serving_size).strip()
                ),
                package_quantity=(
                    source.package_quantity
                    if source.package_quantity > 0.0
                    else normalized.package_quantity
                ),
                package_unit=(
                    source.package_unit
                    if source.package_quantity > 0.0
                    else normalized.package_unit
                )
            )
        );
        idx += 1;
    }
    return restored;
}

def _canonicalize_storage_items(items: list[Ingredient]) -> dict {
    if items == [] {
        return {"items": items, "notes": "", "used_llm": False};
    }
    try {
        normalized = canonicalize_pantry_items_for_storage(items);
        if normalized.items != [] {
            normalized_items = _apply_storage_unit_overrides_batch(
                _restore_source_inventory_fields(normalized.items, items)
            );
            return {
                "items": _ingredients_as_serving_storage(normalized_items),
                "notes": _note_merge(
                    _note_merge(
                        str(normalized.notes).strip(),
                        "Bread-like pantry items are stored in PIECE only when no stronger package mass unit is present."
                    ),
                    "Stored pantry rows as serving-count quantities with USDA serving units and per-serving macros."
                ),
                "used_llm": True
            };
        }
    } except Exception as e {
        return {
            "items": _ingredients_as_serving_storage(_apply_storage_unit_overrides_batch(items)),
            "notes": _note_merge(
                "Pantry unit normalization skipped: {}".format(str(e)),
                _note_merge(
                    "Bread-like pantry items are stored in PIECE only when no stronger package mass unit is present.",
                    "Stored pantry rows as serving-count quantities with USDA serving units and per-serving macros."
                )
            ),
            "used_llm": False
        };
    }
    return {
        "items": _ingredients_as_serving_storage(_apply_storage_unit_overrides_batch(items)),
        "notes": "Bread-like pantry items are stored in PIECE only when no stronger package mass unit is present. | Stored pantry rows as serving-count quantities with USDA serving units and per-serving macros.",
        "used_llm": False
    };
}

def _project_root_candidates() -> list[str] {
    candidates: list = [];
    seen: dict = {};
    start_points = [
        str(os.getcwd()),
        str(os.getenv("PWD", "")),
        str(os.path.abspath(".")),
        str(os.path.abspath("..")),
        str(os.path.abspath("../..")),
        str(os.path.abspath("../../..")),
        str(os.path.abspath("ingredient.jac")),
        str(os.path.abspath("main.jac")),
        str(os.path.abspath("food_data_central_lookup.py"))
    ];

    for start_point in start_points {
        current = str(start_point).strip();
        if current == "" {
            continue;
        }
        if os.path.isfile(current) {
            current = str(os.path.dirname(current)).strip();
        }
        depth = 0;
        while current != "" and depth < 10 {
            if seen.get(current, False) {
                break;
            }
            seen[current] = True;
            if os.path.isfile(os.path.join(current, "food_data_central_lookup.py")) {
                candidates.append(current);
            }
            parent = str(os.path.dirname(current)).strip();
            if parent == "" or parent == current {
                break;
            }
            current = parent;
            depth += 1;
        }
    }
    return candidates;
}

def _ensure_lookup_module_path() -> str {
    for root_dir in _project_root_candidates() {
        present = False;
        for path_row in sys.path {
            if str(path_row).strip() == str(root_dir).strip() {
                present = True;
                break;
            }
        }
        if not present {
            sys.path.append(root_dir);
        }
        try {
            if os.path.isfile(os.path.join(root_dir, "food_data_central_lookup.py")) {
                return root_dir;
            }
        } except Exception as _e {
            0;
        }
    }
    return "";
}

def _fooddata_lookup_module() -> object {
    try {
        return importlib.import_module("food_data_central_lookup");
    } except Exception as first_e {
        root_dir = _ensure_lookup_module_path();
        if root_dir != "" {
            try {
                return importlib.import_module("food_data_central_lookup");
            } except Exception as second_e {
                print("[FoodDataCentral] stage=module_import:error root={} err={}".format(root_dir, str(second_e)));
                raise second_e;
            }
        }
        print("[FoodDataCentral] stage=module_import:error err={}".format(str(first_e)));
        raise first_e;
    }
}

def _fooddata_lookup_payload(ing: Ingredient, store_name: str = "") -> dict {
    lookup_unit = _unit_text(ing.unit);
    if lookup_unit == "LOAF" {
        lookup_unit = "PIECE";
    }
    return {
        "name": ing.name,
        "quantity": ing.quantity,
        "unit": lookup_unit,
        "store_name": str(store_name).strip()
    };
}

def _fooddata_lookup_batch(
    items: list[Ingredient],
    search_hints: list = [],
    store_name: str = ""
) -> dict {
    payload: list = [];
    for ing in items {
        payload.append(_fooddata_lookup_payload(ing, store_name));
    }
    lookup_mod = _fooddata_lookup_module();
    return lookup_mod.lookup_items(payload, search_hints);
}

def _usda_search_hints_for_items(items: list[Ingredient], store_name: str = "") -> dict {
    if items == [] {
        return {"hints": [], "used_llm": False, "notes": ""};
    }

    hint_rows: list = [];
    notes = "";
    used_llm = False;
    try {
        plan = build_usda_food_search_plan(items, store_name);
        used_llm = True;
        notes = str(plan.notes).strip();
        for hint in plan.hints {
            original_name = str(hint.original_name).strip();
            if original_name == "" {
                continue;
            }
            hint_rows.append({
                "original_name": original_name,
                "search_name": str(hint.search_name).strip(),
                "brand_name": str(hint.brand_name).strip(),
                "food_name": str(hint.food_name).strip(),
                "store_name": str(store_name).strip(),
                "preferred_data_types": hint.preferred_data_types,
                "alternate_names": hint.alternate_names,
                "notes": str(hint.notes).strip()
            });
        }
    } except Exception as e {
        notes = "USDA search hint LLM failed: {}".format(str(e));
    }
    return {"hints": hint_rows, "used_llm": used_llm, "notes": notes};
}

def _usda_macro_estimates_for_items(items: list[Ingredient]) -> dict {
    if items == [] {
        return {"items": [], "used_llm": False, "notes": ""};
    }

    rows: list = [];
    notes = "";
    used_llm = False;
    try {
        batch = estimate_missing_item_macros_from_usda(items);
        used_llm = True;
        notes = str(batch.notes).strip();
        for item in batch.items {
            original_name = str(item.original_name).strip();
            if original_name == "" {
                continue;
            }
            rows.append({
                "original_name": original_name,
                "protein": float(item.protein),
                "carb": float(item.carb),
                "fat": float(item.fat),
                "notes": str(item.notes).strip()
            });
        }
    } except Exception as e {
        notes = "USDA macro fallback LLM failed: {}".format(str(e));
    }
    return {"items": rows, "used_llm": used_llm, "notes": notes};
}

def _estimate_map_by_name(rows: list) -> dict {
    mapped: dict = {};
    for row in rows {
        key = _norm_food_name(str(row.get("original_name", "")));
        if key == "" {
            continue;
        }
        mapped[key] = row;
    }
    return mapped;
}

def _ingredient_with_macros(ing: Ingredient, protein: float, carb: float, fat: float) -> Ingredient {
    return Ingredient(
        name=ing.name,
        quantity=ing.quantity,
        unit=ing.unit,
        cost=ing.cost,
        protein=_round_two(protein),
        carb=_round_two(carb),
        fat=_round_two(fat),
        serving_size=ing.serving_size,
        package_quantity=ing.package_quantity,
        package_unit=ing.package_unit
    );
}

def _serving_unit_from_text(serving_size_text: str, fallback_unit: Unit) -> Unit {
    serving_text = _norm_food_name(serving_size_text);
    if serving_text == "" {
        return fallback_unit;
    }
    if "tablespoon" in serving_text or "tbsp" in serving_text {
        return Unit.TBSP;
    }
    if "teaspoon" in serving_text or "tsp" in serving_text {
        return Unit.TSP;
    }
    if "cup" in serving_text {
        return Unit.CUP;
    }
    if "pound" in serving_text or " lb" in " " + serving_text or " lbs" in " " + serving_text {
        return Unit.LB;
    }
    if "ounce" in serving_text or " oz" in " " + serving_text {
        return Unit.OZ;
    }
    if "clove" in serving_text {
        return Unit.CLOVE;
    }
    if "bunch" in serving_text {
        return Unit.BUNCH;
    }
    if "egg" in serving_text or "piece" in serving_text or "whole" in serving_text or "slice" in serving_text or "serving" in serving_text {
        return Unit.PIECE;
    }
    return fallback_unit;
}

def _serving_count_from_lookup_row(lookup_row: dict, fallback_quantity: float) -> float {
    explicit_serving_count = float(lookup_row.get("serving_count", 0.0));
    if explicit_serving_count > 0.0 {
        return explicit_serving_count;
    }
    pairs = [
        [float(lookup_row.get("calories", 0.0)), float(lookup_row.get("serving_calories", 0.0))],
        [float(lookup_row.get("protein", 0.0)), float(lookup_row.get("serving_protein", 0.0))],
        [float(lookup_row.get("carb", 0.0)), float(lookup_row.get("serving_carb", 0.0))],
        [float(lookup_row.get("fat", 0.0)), float(lookup_row.get("serving_fat", 0.0))]
    ];
    for pair in pairs {
        total_amount = float(pair[0]);
        per_serving_amount = float(pair[1]);
        if total_amount > 0.0 and per_serving_amount > 0.0 {
            servings = total_amount / per_serving_amount;
            if servings > 0.0 {
                return servings;
            }
        }
    }
    if fallback_quantity > 0.0 {
        return fallback_quantity;
    }
    return 1.0;
}

def _ingredient_with_lookup_row(ing: Ingredient, lookup_row: dict) -> Ingredient {
    serving_size = str(lookup_row.get("serving_size_text", "")).strip();
    protein = float(lookup_row.get("protein", ing.protein));
    carb = float(lookup_row.get("carb", ing.carb));
    fat = float(lookup_row.get("fat", ing.fat));
    next_quantity = ing.quantity;
    next_unit = ing.unit;
    next_cost = ing.cost;
    package_quantity = ing.package_quantity;
    package_unit = ing.package_unit;
    if package_quantity <= 0.0 {
        package_quantity = ing.quantity;
        package_unit = ing.unit;
    }
    if package_quantity > 0.0 and _is_loaf_style_bread_name(ing.name) and package_unit == Unit.PIECE and package_quantity <= 4.0 {
        package_unit = Unit.LOAF;
    }
    if serving_size != "" {
        protein = float(lookup_row.get("serving_protein", protein));
        carb = float(lookup_row.get("serving_carb", carb));
        fat = float(lookup_row.get("serving_fat", fat));
        next_quantity = _serving_count_from_lookup_row(lookup_row, ing.quantity);
        explicit_serving_unit = str(lookup_row.get("serving_unit_key", "")).strip();
        if explicit_serving_unit != "" {
            next_unit = unit_from_any(explicit_serving_unit);
        } else {
            next_unit = _serving_unit_from_text(serving_size, ing.unit);
        }
        if next_quantity > 0.0 and ing.cost > 0.0 {
            next_cost = ing.cost / next_quantity;
        }
    }
    return Ingredient(
        name=ing.name,
        quantity=_round_two(next_quantity),
        unit=next_unit,
        cost=_round_two(next_cost),
        protein=_round_two(protein),
        carb=_round_two(carb),
        fat=_round_two(fat),
        serving_size=serving_size,
        package_quantity=_round_two(package_quantity),
        package_unit=package_unit
    );
}

def _enrich_items_with_usda_macros(
    items: list[Ingredient],
    context_label: str,
    store_name: str = ""
) -> dict {
    if items == [] {
        return {
            "items": items,
            "notes": "",
            "matched_count": 0,
            "fallback_count": 0,
            "unresolved_count": 0,
            "used_llm_search": False,
            "used_llm_fallback": False
        };
    }

    matched_lookup_rows: dict = {};
    unresolved_indices: list = [];
    used_llm_search = False;
    used_llm_fallback = False;
    matched_count = 0;
    fallback_count = 0;
    summary_note = "";
    lookup_available = True;

    first_lookup: dict = {"ok": False, "results": []};
    try {
        first_lookup = _fooddata_lookup_batch(items, [], store_name);
    } except Exception as e {
        lookup_available = False;
        print("[FoodDataCentral] context={} stage=lookup:error err={}".format(context_label, str(e)));
        summary_note = _note_merge(summary_note, "USDA CSV lookup failed: {}".format(str(e)));
    }

    first_results = first_lookup.get("results", []);
    idx = 0;
    for ing in items {
        row = {};
        if idx < len(first_results) {
            row = first_results[idx];
        }
        if row.get("matched", False) {
            matched_lookup_rows[str(idx)] = row;
            matched_count += 1;
        } else {
            unresolved_indices.append(idx);
            if lookup_available {
                print("[FoodDataCentral] context={} item='{}' stage=csv_miss".format(context_label, ing.name));
            } else {
                print("[FoodDataCentral] context={} item='{}' stage=csv_lookup_unavailable".format(context_label, ing.name));
            }
        }
        idx += 1;
    }

    if unresolved_indices != [] {
        missing_items: list[Ingredient] = [];
        for miss_idx in unresolved_indices {
            missing_items.append(items[miss_idx]);
        }

        hint_out = _usda_search_hints_for_items(missing_items, store_name);
        used_llm_search = hint_out.get("used_llm", False);
        summary_note = _note_merge(summary_note, str(hint_out.get("notes", "")));

        hinted_rows = hint_out.get("hints", []);
        if hinted_rows != [] {
            second_lookup: dict = {"ok": False, "results": []};
            try {
                second_lookup = _fooddata_lookup_batch(missing_items, hinted_rows, store_name);
            } except Exception as e {
                print("[FoodDataCentral] context={} stage=hinted_lookup:error err={}".format(context_label, str(e)));
                summary_note = _note_merge(summary_note, "Hinted USDA CSV lookup failed: {}".format(str(e)));
            }

            second_results = second_lookup.get("results", []);
            still_unresolved: list = [];
            local_idx = 0;
            for miss_idx in unresolved_indices {
                row = {};
                if local_idx < len(second_results) {
                    row = second_results[local_idx];
                }
                if row.get("matched", False) {
                    matched_lookup_rows[str(miss_idx)] = row;
                    matched_count += 1;
                } else {
                    still_unresolved.append(miss_idx);
                }
                local_idx += 1;
            }
            unresolved_indices = still_unresolved;
        }
    }

    estimate_map: dict = {};
    if unresolved_indices != [] {
        fallback_items: list[Ingredient] = [];
        for miss_idx in unresolved_indices {
            fallback_items.append(items[miss_idx]);
        }
        fallback_out = _usda_macro_estimates_for_items(fallback_items);
        used_llm_fallback = fallback_out.get("used_llm", False);
        summary_note = _note_merge(summary_note, str(fallback_out.get("notes", "")));
        estimate_map = _estimate_map_by_name(fallback_out.get("items", []));
    }

    final_items: list[Ingredient] = [];
    still_unresolved_names: list = [];
    idx = 0;
    for ing in items {
        lookup_row = matched_lookup_rows.get(str(idx), None);
        if lookup_row != None {
            final_items.append(_ingredient_with_lookup_row(ing, lookup_row));
            idx += 1;
            continue;
        }

        estimate_row = estimate_map.get(_norm_food_name(ing.name), None);
        if estimate_row != None {
            fallback_count += 1;
            print("[FoodDataCentral] context={} item='{}' stage=llm_fallback".format(context_label, ing.name));
            final_items.append(
                _ingredient_with_macros(
                    ing,
                    float(estimate_row.get("protein", ing.protein)),
                    float(estimate_row.get("carb", ing.carb)),
                    float(estimate_row.get("fat", ing.fat))
                )
            );
            summary_note = _note_merge(summary_note, str(estimate_row.get("notes", "")));
        } else {
            still_unresolved_names.append(ing.name);
            final_items.append(ing);
        }
        idx += 1;
    }

    summary_note = _note_merge(
        summary_note,
        "USDA CSV macros matched {}/{} items.".format(str(matched_count), str(len(items)))
    );
    if fallback_count > 0 {
        summary_note = _note_merge(
            summary_note,
            "LLM USDA macro fallback used for {} items.".format(str(fallback_count))
        );
    }
    if still_unresolved_names != [] {
        summary_note = _note_merge(
            summary_note,
            "No macro source found for: {}".format(", ".join(still_unresolved_names))
        );
    }

    return {
        "items": final_items,
        "notes": summary_note,
        "matched_count": matched_count,
        "fallback_count": fallback_count,
        "unresolved_count": len(still_unresolved_names),
        "used_llm_search": used_llm_search,
        "used_llm_fallback": used_llm_fallback
    };
}

def _fallback_usage_plan(
    pantry_items: list[IndexedPantryIngredient],
    recipe_ingredients: list[Ingredient]
) -> PantryUsagePlan {
    uses: list[PantryUsage] = [];
    used_by_pantry_index: dict = {};
    remaining_by_recipe: list[float] = [];
    for ing in recipe_ingredients {
        remaining_by_recipe.append(ing.quantity);
    }

    recipe_idx = 0;
    for recipe_ing in recipe_ingredients {
        remaining_qty = remaining_by_recipe[recipe_idx];
        recipe_name = _norm_food_name(recipe_ing.name);
        recipe_unit = _unit_text(recipe_ing.unit);
        if remaining_qty <= 0.0 or recipe_name == "" {
            recipe_idx += 1;
            continue;
        }

        while remaining_qty > 0.0 {
            best_match = None;
            best_score = 0.0;
            best_needed_qty = -1.0;
            for pantry_ing in pantry_items {
                pantry_unit = _unit_text(pantry_ing.unit);
                needed_in_pantry_unit = _convert_quantity_between_units(remaining_qty, recipe_unit, pantry_unit);
                if needed_in_pantry_unit <= 0.0 {
                    continue;
                }
                pantry_key = str(pantry_ing.pantry_index);
                prior_used = float(used_by_pantry_index.get(pantry_key, 0.0));
                available = pantry_ing.quantity - prior_used;
                if available <= 0.0 {
                    continue;
                }
                match_score = _food_name_match_score(recipe_ing.name, pantry_ing.name);
                if match_score > best_score {
                    best_score = match_score;
                    best_match = pantry_ing;
                    best_needed_qty = needed_in_pantry_unit;
                }
            }

            if best_match == None or best_score < 55.0 or best_needed_qty <= 0.0 {
                break;
            }

            best_key = str(best_match.pantry_index);
            prior_used = float(used_by_pantry_index.get(best_key, 0.0));
            available = best_match.quantity - prior_used;
            if available <= 0.0 {
                break;
            }
            used_qty = best_needed_qty;
            if used_qty > available {
                used_qty = available;
            }
            if used_qty <= 0.0 {
                break;
            }
            consumed_recipe_qty = _convert_quantity_between_units(
                used_qty,
                _unit_text(best_match.unit),
                recipe_unit
            );
            if consumed_recipe_qty <= 0.0 {
                break;
            }

            uses.append(
                PantryUsage(
                    pantry_index=best_match.pantry_index,
                    quantity_used=used_qty,
                    reason="Deterministic pantry match"
                )
            );
            used_by_pantry_index[best_key] = prior_used + used_qty;
            remaining_qty = remaining_qty - consumed_recipe_qty;
        }
        recipe_idx += 1;
    }
    return PantryUsagePlan(
        uses=uses,
        notes="Used deterministic pantry subtraction."
    );
}

def _apply_usage_plan_to_pantry(pantry_rows: list[dict], usage_plan: PantryUsagePlan) -> list {
    used_totals: dict = {};
    for use in usage_plan.uses {
        pantry_index = int(use.pantry_index);
        if pantry_index < 0 or pantry_index >= len(pantry_rows) {
            continue;
        }
        use_qty = float(use.quantity_used);
        if use_qty <= 0.0 {
            continue;
        }
        row = pantry_rows[pantry_index];
        row_qty = float(row.get("quantity", 0.0));
        prior_used = float(used_totals.get(str(pantry_index), 0.0));
        available = row_qty - prior_used;
        if available <= 0.0 {
            continue;
        }
        if use_qty > available {
            use_qty = available;
        }
        used_totals[str(pantry_index)] = prior_used + use_qty;
    }

    updated_rows: list = [];
    idx = 0;
    for row in pantry_rows {
        row_qty = float(row.get("quantity", 0.0));
        used_qty = float(used_totals.get(str(idx), 0.0));
        remaining_qty = row_qty - used_qty;
        idx += 1;
        if remaining_qty <= 0.0001 {
            continue;
        }
        keep_ratio = 1.0;
        if row_qty > 0.0 {
            keep_ratio = remaining_qty / row_qty;
        }
        updated_rows.append({
            "name": str(row.get("name", "")).strip(),
            "quantity": _round_two(remaining_qty),
            "unit": _unit_text(row.get("unit", "PIECE")),
            "cost": _round_two(float(row.get("cost", 0.0))),
            "protein": _round_two(float(row.get("protein", 0.0))),
            "carb": _round_two(float(row.get("carb", 0.0))),
            "fat": _round_two(float(row.get("fat", 0.0))),
            "serving_size": str(row.get("serving_size", "")).strip(),
            "package_quantity": _round_two(float(row.get("package_quantity", 0.0)) * keep_ratio),
            "package_unit": _unit_text(row.get("package_unit", row.get("unit", "PIECE")))
        });
    }
    return updated_rows;
}

# Persisted recipe summary node.
node Recipe {
    has name: str,
        instructions: list[str],
        total_calories: float,
        total_protein_g: float,
        total_carbs_g: float,
        total_fat_g: float,
        recipe_id: str = "",
        generated_at_ms: int = 0;
}

# Persisted ingredient rows for the latest generated recipe.
node MealIngredient {
    has name: str,
        quantity: float,
        unit: str,
        cost: float,
        protein: float,
        carb: float,
        fat: float,
        recipe_id: str = "";
}

node RecipeHistoryEntry {
    has recipe_id: str,
        title: str,
        total_calories: float,
        total_protein_g: float,
        total_carbs_g: float,
        total_fat_g: float,
        generated_at_ms: int,
        instructions: list = [],
        ingredients: list = [],
        rating: float = 0.0,
        rating_tier: str = "",
        rating_order: int = -1,
        favorite: bool = False,
        made: bool = False,
        made_at_ms: int = 0,
        notes: str = "Generated from your profile + pantry";
}

# Main recipe generation workflow:
# 1) clear old recipe state
# 2) generate new recipe with LLM
# 3) persist recipe + ingredients
# 4) return response payload for frontend rendering
walker GenerateRecipeFromPantry {
    has profile: dict;
    has pantry_ingredients: list[dict];
    has new_recipe_nodes: list = [];
    has new_history_nodes: list = [];
    has new_ingredient_nodes: list = [];

    can generate with Root entry {
        try {
            visit [-->];

            profile_obj = user_from_dict(self.profile);
            pantry_typed: list[Ingredient] = [];
            for row in self.pantry_ingredients {
                try {
                    pantry_typed.append(ingredient_from_payload(row));
                } except Exception as row_e {
                    report {
                        "ok": False,
                        "error": "Invalid pantry ingredient payload: {}".format(str(row_e))
                    };
                    return;
                }
            }

            plan = generate_recipe(profile_obj, pantry_typed);
            recipe_id = str(uuid.uuid4());
            generated_at_ms = _now_ms();

            self.new_recipe_nodes = here ++> Recipe(
                recipe_id=recipe_id,
                name=plan.recipe_name,
                instructions=plan.instructions,
                total_calories=plan.total_calories,
                total_protein_g=plan.total_protein_g,
                total_carbs_g=plan.total_carbs_g,
                total_fat_g=plan.total_fat_g,
                generated_at_ms=generated_at_ms
            );

            result: list = [];
            for ing in plan.recipe_ingredients {
                ing_data = ingredient_to_payload(ing);
                ing_data["unit"] = str(ing.unit).split(".")[-1].lower();
                new_ing_nodes = here ++> MealIngredient(
                    name=ing_data["name"],
                    quantity=ing_data["quantity"],
                    unit=ing_data["unit"],
                    cost=ing_data["cost"],
                    protein=ing_data["protein"],
                    carb=ing_data["carb"],
                    fat=ing_data["fat"],
                    recipe_id=recipe_id
                );
                self.new_ingredient_nodes.extend(new_ing_nodes);
                result.append(ing_data);
            }

            self.new_history_nodes = here ++> RecipeHistoryEntry(
                recipe_id=recipe_id,
                title=plan.recipe_name,
                total_calories=plan.total_calories,
                total_protein_g=plan.total_protein_g,
                total_carbs_g=plan.total_carbs_g,
                total_fat_g=plan.total_fat_g,
                instructions=plan.instructions,
                ingredients=result,
                generated_at_ms=generated_at_ms
            );

            if len(self.new_recipe_nodes) > 0 {
                save(self.new_recipe_nodes[0]);
            }
            if len(self.new_history_nodes) > 0 {
                save(self.new_history_nodes[0]);
            }
            for ingredient_node in self.new_ingredient_nodes {
                save(ingredient_node);
            }
            commit();

            report {
                "ok": True,
                "recipe_id": recipe_id,
                "recipe_name": plan.recipe_name,
                "instructions": plan.instructions,
                "ingredients": result,
                "total_calories": plan.total_calories,
                "total_protein_g": plan.total_protein_g,
                "total_carbs_g": plan.total_carbs_g,
                "total_fat_g": plan.total_fat_g,
                "generated_at_ms": generated_at_ms,
                "favorite": False,
                "made": False,
                "made_at_ms": 0,
                "rating": 0.0,
                "rating_tier": "",
                "rating_order": -1,
                "notes": "Generated from your profile + pantry"
            };
        } except Exception as e {
            report {
                "ok": False,
                "error": str(e)
            };
        }
    }

    can clear_old_recipe with Recipe entry {
        # Keep only the latest generated recipe.
        del here;
    }

    can clear_old_ingredients with MealIngredient entry {
        # Keep ingredient list aligned with latest generated recipe.
        del here;
    }
}

# Read back the latest generated recipe from graph storage.
walker ListGeneratedRecipe {
    has recipe: dict = {};
    has ingredient_rows: list = [];
    has found_recipe: bool = False;
    has best_recipe_id: str = "";
    has best_generated_at_ms: int = -1;

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with Recipe entry {
        recipe_generated_at_ms = int(here.generated_at_ms);
        if self.found_recipe and recipe_generated_at_ms < self.best_generated_at_ms {
            return;
        }
        self.found_recipe = True;
        self.best_recipe_id = here.recipe_id;
        self.best_generated_at_ms = recipe_generated_at_ms;
        self.recipe = {
            "recipe_id": here.recipe_id,
            "recipe_name": here.name,
            "instructions": here.instructions,
            "total_calories": here.total_calories,
            "total_protein_g": here.total_protein_g,
            "total_carbs_g": here.total_carbs_g,
            "total_fat_g": here.total_fat_g,
            "generated_at_ms": here.generated_at_ms
        };
    }

    can read_ingredients with MealIngredient entry {
        self.ingredient_rows.append({
            "recipe_id": here.recipe_id,
            "name": here.name,
            "quantity": here.quantity,
            "unit": here.unit,
            "cost": here.cost,
            "protein": here.protein,
            "carb": here.carb,
            "fat": here.fat
        });
    }

    can report_all with Root exit {
        if not self.found_recipe {
            report {};
            return;
        }
        filtered_ingredients: list = [];
        for row in self.ingredient_rows {
            if str(row.get("recipe_id", "")).strip() != self.best_recipe_id {
                continue;
            }
            filtered_ingredients.append({
                "name": row.get("name", ""),
                "quantity": row.get("quantity", 0.0),
                "unit": row.get("unit", ""),
                "cost": row.get("cost", 0.0),
                "protein": row.get("protein", 0.0),
                "carb": row.get("carb", 0.0),
                "fat": row.get("fat", 0.0)
            });
        }
        self.recipe["ingredients"] = filtered_ingredients;
        report self.recipe;
    }
}

walker ListRecipeHistory {
    has recipes: list = [];

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with RecipeHistoryEntry entry {
        recipe_id = _ensure_history_recipe_id(here);
        self.recipes.append({
            "recipe_id": recipe_id,
            "title": _history_title(here),
            "total_calories": _history_total_calories(here),
            "total_protein_g": _history_total_protein_g(here),
            "total_carbs_g": _history_total_carbs_g(here),
            "total_fat_g": _history_total_fat_g(here),
            "generated_at_ms": _history_generated_at_ms(here),
            "rating": _history_rating(here),
            "rating_tier": _history_rating_tier(here),
            "rating_order": _history_rating_order(here),
            "favorite": _history_favorite(here),
            "made": _history_made(here),
            "made_at_ms": _history_made_at_ms(here),
            "notes": _history_notes(here),
            "instructions": _history_instructions(here),
            "ingredients": _history_ingredients(here)
        });
    }

    can report_all with Root exit {
        report self.recipes;
    }
}

walker SetRecipeFavorite {
    has recipe_id: str;
    has favorite: bool;
    has updated: bool = False;
    has title: str = "";
    has total_calories: float = 0.0;
    has total_protein_g: float = 0.0;
    has total_carbs_g: float = 0.0;
    has total_fat_g: float = 0.0;
    has generated_at_ms: int = 0;
    has rating: float = 0.0;
    has rating_tier: str = "";
    has rating_order: int = -1;
    has notes: str = "Generated from your profile + pantry";

    can collect with Root entry {
        visit [-->];
    }

    can stage_update with RecipeHistoryEntry entry {
        if _ensure_history_recipe_id(here) != self.recipe_id {
            return;
        }
        self.updated = True;
        self.title = _history_title(here);
        self.total_calories = _history_total_calories(here);
        self.total_protein_g = _history_total_protein_g(here);
        self.total_carbs_g = _history_total_carbs_g(here);
        self.total_fat_g = _history_total_fat_g(here);
        self.generated_at_ms = _history_generated_at_ms(here);
        self.rating = _history_rating(here);
        self.rating_tier = _history_rating_tier(here);
        self.rating_order = _history_rating_order(here);
        self.notes = _history_notes(here);
        here.favorite = self.favorite;
    }

    can finish with Root exit {
        if not self.updated {
            report {"updated": False, "error": "Recipe not found"};
            return;
        }
        report {
            "updated": True,
            "recipe_id": self.recipe_id,
            "favorite": self.favorite,
            "rating": self.rating,
            "rating_tier": self.rating_tier,
            "rating_order": self.rating_order
        };
    }
}

walker MarkRecipeMade {
    has recipe_id: str;
    has made: bool = True;
    has made_at_ms: int = 0;
    has updated: bool = False;
    has current_title: str = "";
    has current_total_calories: float = 0.0;
    has current_total_protein_g: float = 0.0;
    has current_total_carbs_g: float = 0.0;
    has current_total_fat_g: float = 0.0;
    has current_instructions: list = [];
    has current_ingredients: list = [];
    has current_generated_at_ms: int = 0;
    has found_current_recipe: bool = False;
    has touched_history_nodes: list = [];
    has created_history_nodes: list = [];
    has cleared_generated: bool = False;

    can collect with Root entry {
        if self.made and self.made_at_ms <= 0 {
            self.made_at_ms = _now_ms();
        }
        visit [-->];
    }

    can stage_current_recipe with Recipe entry {
        if here.recipe_id != self.recipe_id {
            return;
        }
        self.found_current_recipe = True;
        self.current_title = here.name;
        self.current_total_calories = here.total_calories;
        self.current_total_protein_g = here.total_protein_g;
        self.current_total_carbs_g = here.total_carbs_g;
        self.current_total_fat_g = here.total_fat_g;
        self.current_instructions = here.instructions;
        self.current_generated_at_ms = here.generated_at_ms;
        self.cleared_generated = True;
        del here;
    }

    can clear_generated_ingredient with MealIngredient entry {
        if here.recipe_id != self.recipe_id {
            return;
        }
        self.current_ingredients.append({
            "name": here.name,
            "quantity": here.quantity,
            "unit": here.unit,
            "cost": here.cost,
            "protein": here.protein,
            "carb": here.carb,
            "fat": here.fat
        });
        self.cleared_generated = True;
        del here;
    }

    can mark_recipe with RecipeHistoryEntry entry {
        if _ensure_history_recipe_id(here) != self.recipe_id {
            return;
        }
        self.updated = True;
        if _history_instructions(here) == [] and self.current_instructions != [] {
            here.instructions = self.current_instructions;
        }
        if _history_ingredients(here) == [] and self.current_ingredients != [] {
            here.ingredients = self.current_ingredients;
        }
        here.made = self.made;
        if self.made {
            here.made_at_ms = self.made_at_ms;
        } else {
            here.made_at_ms = 0;
        }
        self.touched_history_nodes.append(here);
    }

    can finish with Root exit {
        if not self.updated and self.found_current_recipe {
            self.created_history_nodes = here ++> RecipeHistoryEntry(
                recipe_id=self.recipe_id,
                title=self.current_title,
                total_calories=self.current_total_calories,
                total_protein_g=self.current_total_protein_g,
                total_carbs_g=self.current_total_carbs_g,
                total_fat_g=self.current_total_fat_g,
                instructions=self.current_instructions,
                ingredients=self.current_ingredients,
                generated_at_ms=(self.current_generated_at_ms if self.current_generated_at_ms > 0 else _now_ms()),
                made=self.made,
                made_at_ms=(self.made_at_ms if self.made else 0)
            );
            self.updated = True;
        }
        if not self.updated {
            report {"updated": False, "error": "Recipe not found"};
            return;
        }
        try {
            for history_node in self.touched_history_nodes {
                save(history_node);
            }
            for history_node in self.created_history_nodes {
                save(history_node);
            }
            commit();
        } except Exception as persist_e {
            report {"updated": False, "error": str(persist_e)};
            return;
        }
        report {
            "updated": True,
            "recipe_id": self.recipe_id,
            "made": self.made,
            "made_at_ms": (self.made_at_ms if self.made else 0),
            "cleared_generated": self.cleared_generated
        };
    }
}

walker SaveRecipeRankingBatch {
    has updates: list[dict];
    has update_map: dict = {};
    has legacy_update_map: dict = {};
    has scored_updates: list = [];
    has applied_updates: list = [];
    has expected_count: int = 0;
    has updated_count: int = 0;

    can collect with Root entry {
        tier_rows: dict = {};
        for row in self.updates {
            tier_name = str(row.get("rating_tier", "")).strip().lower();
            if tier_name == "" {
                continue;
            }
            rows_for_tier = tier_rows.get(tier_name, None);
            if rows_for_tier == None {
                rows_for_tier = [];
            }
            rows_for_tier.append(row);
            tier_rows[tier_name] = rows_for_tier;
        }

        for tier_name in ["very_good", "average", "not_great"] {
            rows_for_tier = tier_rows.get(tier_name, None);
            if rows_for_tier == None or len(rows_for_tier) == 0 {
                continue;
            }
            self.scored_updates.extend(
                _scored_rank_updates_for_tier(tier_name, rows_for_tier)
            );
        }

        for row in self.scored_updates {
            recipe_id = str(row.get("recipe_id", "")).strip();
            if recipe_id != "" {
                if self.update_map.get(recipe_id, None) == None {
                    self.expected_count += 1;
                }
                self.update_map[recipe_id] = row;
                continue;
            }
            legacy_key = _history_legacy_key(
                row.get("title", ""),
                row.get("generated_at_ms", 0)
            );
            if legacy_key == "" {
                continue;
            }
            if self.legacy_update_map.get(legacy_key, None) == None {
                self.expected_count += 1;
            }
            self.legacy_update_map[legacy_key] = row;
        }
        if self.expected_count == 0 {
            return;
        }
        visit [-->];
    }

    can apply_update with RecipeHistoryEntry entry {
        recipe_id = _ensure_history_recipe_id(here);
        if recipe_id == "" {
            legacy_key = _history_legacy_key(
                _history_title(here),
                _history_generated_at_ms(here)
            );
            row = self.legacy_update_map.get(legacy_key, None);
        } else {
            row = self.update_map.get(recipe_id, None);
        }
        if row == None {
            legacy_key = _history_legacy_key(
                _history_title(here),
                _history_generated_at_ms(here)
            );
            row = self.legacy_update_map.get(legacy_key, None);
        }
        if row == None {
            return;
        }

        safe_rating = float(row.get("rating", 0.0));
        if safe_rating < 0.0 {
            safe_rating = 0.0;
        } elif safe_rating > 10.0 {
            safe_rating = 10.0;
        }

        here.rating = safe_rating;
        here.rating_tier = str(row.get("rating_tier", "")).strip().lower();
        here.rating_order = int(row.get("rating_order", -1));
        self.updated_count += 1;
        self.applied_updates.append({
            "recipe_id": recipe_id,
            "recipe_key": str(row.get("recipe_key", recipe_id)).strip(),
            "title": _history_title(here),
            "generated_at_ms": _history_generated_at_ms(here),
            "rating": safe_rating,
            "rating_tier": here.rating_tier,
            "rating_order": here.rating_order
        });
    }

    can finish with Root exit {
        if self.expected_count == 0 {
            report {"updated": False, "error": "No ranking updates provided", "updated_count": 0, "updates": []};
            return;
        }
        report {
            "updated": self.updated_count == self.expected_count,
            "updated_count": self.updated_count,
            "expected_count": self.expected_count,
            "updates": self.applied_updates
        };
    }
}

walker DeleteSavedRecipe {
    has recipe_id: str;
    has deleted_history: bool = False;
    has deleted_current_recipe: bool = False;
    has deleted_any: bool = False;

    can collect with Root entry {
        visit [-->];
    }

    can delete_history with RecipeHistoryEntry entry {
        if _ensure_history_recipe_id(here) == self.recipe_id {
            self.deleted_history = True;
            self.deleted_any = True;
            del here;
        }
    }

    can delete_current_recipe with Recipe entry {
        if here.recipe_id == self.recipe_id {
            self.deleted_current_recipe = True;
            self.deleted_any = True;
            del here;
        }
    }

    can delete_current_ingredients with MealIngredient entry {
        if here.recipe_id == self.recipe_id {
            self.deleted_any = True;
            del here;
        }
    }

    can finish with Root exit {
        if not self.deleted_history and not self.deleted_current_recipe {
            report {"deleted": False, "error": "Recipe not found"};
            return;
        }
        if self.deleted_any {
            try {
                commit();
            } except Exception as persist_e {
                report {"deleted": False, "error": str(persist_e)};
                return;
            }
        }
        report {
            "deleted": True,
            "deleted_current_recipe": self.deleted_current_recipe
        };
    }
}

# Clear persisted recipe state.
walker ClearGeneratedRecipe {
    has cleared_any: bool = False;

    can collect with Root entry {
        visit [-->];
    }

    can clear_recipe with Recipe entry {
        self.cleared_any = True;
        del here;
    }

    can clear_ingredients with MealIngredient entry {
        self.cleared_any = True;
        del here;
    }

    can done with Root exit {
        if self.cleared_any {
            try {
                commit();
            } except Exception as persist_e {
                report {"cleared": False, "error": str(persist_e)};
                return;
            }
        }
        report {"cleared": True};
    }
}

walker ComputePantryAfterRecipe {
    has pantry_items: list[dict];
    has recipe_ingredients: list[dict];

    can run with Root entry {
        try {
            pantry_rows: list[dict] = [];
            indexed_pantry: list[IndexedPantryIngredient] = [];
            pantry_index = 0;
            for row in self.pantry_items {
                typed = ingredient_from_payload(row);
                pantry_rows.append(ingredient_to_payload(typed));
                indexed_pantry.append(
                    IndexedPantryIngredient(
                        pantry_index=pantry_index,
                        name=typed.name,
                        quantity=typed.quantity,
                        unit=typed.unit,
                        cost=typed.cost,
                        protein=typed.protein,
                        carb=typed.carb,
                        fat=typed.fat
                    )
                );
                pantry_index += 1;
            }

            recipe_typed: list[Ingredient] = [];
            for row in self.recipe_ingredients {
                recipe_typed.append(ingredient_from_payload(row));
            }

            usage_plan = _fallback_usage_plan(indexed_pantry, recipe_typed);
            used_llm = False;
            notes = str(usage_plan.notes).strip();

            updated_pantry = _apply_usage_plan_to_pantry(pantry_rows, usage_plan);
            report {
                "ok": True,
                "updated_pantry": updated_pantry,
                "used_llm": used_llm,
                "notes": _note_merge(notes, usage_plan.notes)
            };
        } except Exception as e {
            report {
                "ok": False,
                "updated_pantry": self.pantry_items,
                "error": str(e)
            };
        }
    }
}

# Convert receipt image directly into pantry ingredients with a single LLM call.
walker ParseReceiptImageToPantry {
    has image_base64: str;
    has image_mime_type: str = "image/jpeg";

    can run with Root entry {
        try {
            request_id = str(uuid.uuid4());
            started_ms = _now_ms();
            ocr_ms = -1;
            llm_ms = -1;
            if str(self.image_base64).strip() == "" {
                report {
                    "ok": False,
                    "stage": "validation",
                    "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                    "items": [],
                    "receipt_total": 0.0,
                    "parsed_items_total": 0.0,
                    "total_delta": 0.0,
                    "notes": "Empty image payload",
                    "error": "No receipt image was provided."
                };
                return;
            }

            print("[ParseReceiptImageToPantry] request_id={} stage=ocr:start".format(request_id));
            ocr_started_ms = _now_ms();
            ocr = extract_receipt_text(
                self.image_base64,
                True,
                ["en"],
                False,
                False
            );
            ocr_ms = _now_ms() - ocr_started_ms;
            print("[ParseReceiptImageToPantry] request_id={} stage=ocr:end ocr_ms={}".format(request_id, ocr_ms));
            if ocr["ok"] == False {
                report {
                    "ok": False,
                    "stage": "ocr",
                    "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                    "items": [],
                    "receipt_total": 0.0,
                    "parsed_items_total": 0.0,
                    "total_delta": 0.0,
                    "notes": "OCR failed before LLM parse",
                    "error": str(ocr.get("error", "OCR failed"))
                };
                return;
            }

            text_in = str(ocr.get("text", "")).strip();
            if text_in == "" {
                report {
                    "ok": False,
                    "stage": "ocr",
                    "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                    "items": [],
                    "receipt_total": 0.0,
                    "parsed_items_total": 0.0,
                    "total_delta": 0.0,
                    "notes": "OCR produced empty text",
                    "error": "No readable receipt text was detected."
                };
                return;
            }

            print("[ParseReceiptImageToPantry] request_id={} stage=llm:start".format(request_id));
            llm_started_ms = _now_ms();
            parsed = None;
            try {
                parsed = parse_receipt_text_into_pantry_items(text_in);
            } except Exception as llm_e {
                llm_ms = _now_ms() - llm_started_ms;
                print("[ParseReceiptImageToPantry] request_id={} stage=llm:error llm_ms={} err={}".format(request_id, llm_ms, str(llm_e)));
                fallback_items = _fallback_extract_items_from_ocr_text(text_in);
                if fallback_items != [] {
                    fallback_total = 0.0;
                    for it in fallback_items {
                        fallback_total += float(it["cost"]);
                    }
                    report {
                        "ok": True,
                        "stage": "llm_fallback",
                        "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                        "items": fallback_items,
                        "store_name": "",
                        "subtotal": 0.0,
                        "tax": 0.0,
                        "extracted_text": text_in,
                        "receipt_total": 0.0,
                        "parsed_items_total": fallback_total,
                        "total_delta": fallback_total,
                        "total_match": False,
                        "notes": "LLM parse failed; fallback OCR line parser was used.",
                        "error": ""
                    };
                    return;
                }
                report {
                    "ok": False,
                    "stage": "llm",
                    "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                    "items": [],
                    "extracted_text": text_in,
                    "error": str(llm_e)
                };
                return;
            }
            llm_ms = _now_ms() - llm_started_ms;
            print("[ParseReceiptImageToPantry] request_id={} stage=llm:end llm_ms={}".format(request_id, llm_ms));
            raw_items_typed: list[Ingredient] = [];
            parsed_items_total = 0.0;
            for ing in parsed.food_line_items {
                if str(ing.name).strip() == "" {
                    continue;
                }
                if ing.quantity <= 0 {
                    continue;
                }
                if ing.cost < 0 {
                    continue;
                }
                raw_items_typed.append(ing);
                parsed_items_total += ing.cost;
            }
            raw_items_typed = _apply_inline_amount_cleanup(raw_items_typed, "receipt_image");
            nutrition_out = _enrich_items_with_usda_macros(raw_items_typed, "receipt_image", parsed.store_name);
            nutrition_notes = str(nutrition_out.get("notes", "")).strip();
            raw_items_typed = nutrition_out.get("items", raw_items_typed);
            canonical_out = _canonicalize_storage_items(raw_items_typed);
            final_items_typed = canonical_out.get("items", raw_items_typed);
            canonical_notes = str(canonical_out.get("notes", "")).strip();
            items: list = [];
            for ing in final_items_typed {
                if str(ing.name).strip() == "" or ing.quantity <= 0 {
                    continue;
                }
                items.append(ingredient_to_payload(ing));
            }

            receipt_total = parsed.receipt_total;
            total_delta = parsed_items_total - receipt_total;
            if total_delta < 0 {
                total_delta = 0 - total_delta;
            }
            allowed_delta = max(1.50, receipt_total * 0.05);
            total_match = False;
            if receipt_total > 0 {
                total_match = total_delta <= allowed_delta;
            }

            if not total_match {
                mismatch_note = "Warning: receipt total mismatch. Parsed item sum may be incomplete due to OCR quality.";
                merged_notes = _note_merge(parsed.notes, nutrition_notes);
                merged_notes = _note_merge(merged_notes, canonical_notes);
                merged_notes = _note_merge(merged_notes, mismatch_note);

                if items == [] {
                    fallback_items = _fallback_extract_items_from_ocr_text(text_in);
                    if fallback_items != [] {
                        fallback_total = 0.0;
                        for it in fallback_items {
                            fallback_total += float(it["cost"]);
                        }
                        report {
                            "ok": True,
                            "stage": "llm_fallback",
                            "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                            "items": fallback_items,
                            "receipt_total": receipt_total,
                            "parsed_items_total": fallback_total,
                            "total_delta": total_delta,
                            "total_match": False,
                            "notes": "{} | Used fallback OCR line parser due to LLM extraction failure.".format(merged_notes),
                            "nutrition_lookup": {
                                "matched_count": nutrition_out.get("matched_count", 0),
                                "fallback_count": nutrition_out.get("fallback_count", 0),
                                "unresolved_count": nutrition_out.get("unresolved_count", 0),
                                "used_llm_search": nutrition_out.get("used_llm_search", False),
                                "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                            },
                            "error": ""
                        };
                        return;
                    }
                    report {
                        "ok": True,
                        "stage": "llm",
                        "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                        "items": items,
                        "receipt_total": receipt_total,
                        "parsed_items_total": parsed_items_total,
                        "total_delta": total_delta,
                        "total_match": False,
                        "notes": merged_notes,
                        "nutrition_lookup": {
                            "matched_count": nutrition_out.get("matched_count", 0),
                            "fallback_count": nutrition_out.get("fallback_count", 0),
                            "unresolved_count": nutrition_out.get("unresolved_count", 0),
                            "used_llm_search": nutrition_out.get("used_llm_search", False),
                            "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                        },
                        "error": ""
                    };
                    return;
                }

                report {
                    "ok": True,
                    "stage": "llm",
                    "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                    "items": items,
                    "receipt_total": receipt_total,
                    "parsed_items_total": parsed_items_total,
                    "total_delta": total_delta,
                    "total_match": False,
                    "notes": merged_notes,
                    "nutrition_lookup": {
                        "matched_count": nutrition_out.get("matched_count", 0),
                        "fallback_count": nutrition_out.get("fallback_count", 0),
                        "unresolved_count": nutrition_out.get("unresolved_count", 0),
                        "used_llm_search": nutrition_out.get("used_llm_search", False),
                        "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                    },
                    "error": ""
                };
                return;
            }

            report {
                "ok": True,
                "stage": "llm",
                "diagnostics": _diag_payload(request_id, started_ms, ocr_ms, llm_ms),
                "items": items,
                "store_name": parsed.store_name,
                "subtotal": parsed.subtotal,
                "tax": parsed.tax,
                "extracted_text": text_in,
                "receipt_total": receipt_total,
                "parsed_items_total": parsed_items_total,
                "total_delta": total_delta,
                "total_match": True,
                "notes": _note_merge(_note_merge(parsed.notes, nutrition_notes), canonical_notes),
                "nutrition_lookup": {
                    "matched_count": nutrition_out.get("matched_count", 0),
                    "fallback_count": nutrition_out.get("fallback_count", 0),
                    "unresolved_count": nutrition_out.get("unresolved_count", 0),
                    "used_llm_search": nutrition_out.get("used_llm_search", False),
                    "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                }
            };
        } except Exception as e {
            report {
                "ok": False,
                "stage": "server",
                "items": [],
                "error": str(e)
            };
        }
    }
}

# Convert OCR text into pantry ingredients with a single LLM call.
walker ParseReceiptTextToPantry {
    has receipt_text: str;

    can run with Root entry {
        try {
            text_in = str(self.receipt_text).strip();
            if text_in == "" {
                report {
                    "ok": False,
                    "items": [],
                    "receipt_total": 0.0,
                    "parsed_items_total": 0.0,
                    "total_delta": 0.0,
                    "notes": "Empty receipt text provided - no content to parse",
                    "error": "Empty OCR text. Receipt parser was not run."
                };
                return;
            }

            parsed = parse_receipt_text_into_pantry_items(text_in);
            raw_items_typed: list[Ingredient] = [];
            parsed_items_total = 0.0;
            for ing in parsed.food_line_items {
                if str(ing.name).strip() == "" {
                    continue;
                }
                if ing.quantity <= 0 {
                    continue;
                }
                if ing.cost < 0 {
                    continue;
                }
                raw_items_typed.append(ing);
                parsed_items_total += ing.cost;
            }
            raw_items_typed = _apply_inline_amount_cleanup(raw_items_typed, "receipt_text");
            nutrition_out = _enrich_items_with_usda_macros(raw_items_typed, "receipt_text", parsed.store_name);
            nutrition_notes = str(nutrition_out.get("notes", "")).strip();
            raw_items_typed = nutrition_out.get("items", raw_items_typed);
            canonical_out = _canonicalize_storage_items(raw_items_typed);
            final_items_typed = canonical_out.get("items", raw_items_typed);
            canonical_notes = str(canonical_out.get("notes", "")).strip();
            items: list = [];
            for ing in final_items_typed {
                if str(ing.name).strip() == "" or ing.quantity <= 0 {
                    continue;
                }
                items.append(ingredient_to_payload(ing));
            }

            receipt_total = parsed.receipt_total;
            total_delta = parsed_items_total - receipt_total;
            if total_delta < 0 {
                total_delta = 0 - total_delta;
            }
            allowed_delta = max(1.50, receipt_total * 0.05);
            total_match = False;
            if receipt_total > 0 {
                total_match = total_delta <= allowed_delta;
            } else {
                # Allow no-total receipts only when we still extracted plausible items.
                total_match = items != [];
            }

            if not total_match {
                mismatch_note = "Warning: receipt total mismatch. Parsed item sum may be incomplete due to OCR quality.";
                merged_notes = _note_merge(parsed.notes, nutrition_notes);
                merged_notes = _note_merge(merged_notes, canonical_notes);
                merged_notes = _note_merge(merged_notes, mismatch_note);

                if items == [] {
                    report {
                        "ok": False,
                        "items": items,
                        "receipt_total": receipt_total,
                        "parsed_items_total": parsed_items_total,
                        "total_delta": total_delta,
                        "total_match": False,
                        "notes": merged_notes,
                        "nutrition_lookup": {
                            "matched_count": nutrition_out.get("matched_count", 0),
                            "fallback_count": nutrition_out.get("fallback_count", 0),
                            "unresolved_count": nutrition_out.get("unresolved_count", 0),
                            "used_llm_search": nutrition_out.get("used_llm_search", False),
                            "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                        },
                        "error": "Receipt total mismatch. Parsed item sum does not match printed receipt total."
                    };
                    return;
                }

                report {
                    "ok": True,
                    "items": items,
                    "receipt_total": receipt_total,
                    "parsed_items_total": parsed_items_total,
                    "total_delta": total_delta,
                    "total_match": False,
                    "notes": merged_notes,
                    "nutrition_lookup": {
                        "matched_count": nutrition_out.get("matched_count", 0),
                        "fallback_count": nutrition_out.get("fallback_count", 0),
                        "unresolved_count": nutrition_out.get("unresolved_count", 0),
                        "used_llm_search": nutrition_out.get("used_llm_search", False),
                        "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                    },
                    "error": ""
                };
                return;
            }

            report {
                "ok": True,
                "items": items,
                "store_name": parsed.store_name,
                "subtotal": parsed.subtotal,
                "tax": parsed.tax,
                "extracted_text": parsed.extracted_text,
                "receipt_total": receipt_total,
                "parsed_items_total": parsed_items_total,
                "total_delta": total_delta,
                "total_match": True,
                "notes": _note_merge(_note_merge(parsed.notes, nutrition_notes), canonical_notes),
                "nutrition_lookup": {
                    "matched_count": nutrition_out.get("matched_count", 0),
                    "fallback_count": nutrition_out.get("fallback_count", 0),
                    "unresolved_count": nutrition_out.get("unresolved_count", 0),
                    "used_llm_search": nutrition_out.get("used_llm_search", False),
                    "used_llm_fallback": nutrition_out.get("used_llm_fallback", False)
                }
            };
        } except Exception as e {
            report {
                "ok": False,
                "items": [],
                "error": str(e)
            };
        }
    }
}
