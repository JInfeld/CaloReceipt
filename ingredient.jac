"""Ingredient module wiring.
Generate a recipe from a user profile and available pantry ingredients.
"""

import from llm_config {
    llm
}
import time;
import uuid;

import from receipt {
    extract_receipt_text
}

import from user {
    user,
    user_from_dict
}

enum Unit { PIECE, LB, OZ, CUP, TBSP, TSP, CLOVE, BUNCH }

# Pantry/recipe ingredient schema shared by frontend payloads and LLM output.
obj Ingredient {
    has name: str;
    has quantity: float;
    has unit: Unit;
    has cost: float;
    has protein: float;
    has carb: float;
    has fat: float;
}

sem Ingredient.cost = "Estimated cost in USD";
sem Ingredient.protein = "Estimated amount of protein in grams";
sem Ingredient.carb = "Estimated amount of carbohydrate in grams";
sem Ingredient.fat = "Estimated amount of fat in grams";

obj RecipePlan {
    has recipe_name: str;
    has instructions: list[str];
    has recipe_ingredients: list[Ingredient];
    has total_calories: float;
    has total_protein_g: float;
    has total_carbs_g: float;
    has total_fat_g: float;
}

"""Generate a recipe using the user's profile and pantry ingredients."""
def generate_recipe(profile: user, pantry_ingredients: list[Ingredient]) -> RecipePlan by llm();

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

"""Normalize pantry inventory into recipe-friendly kitchen units.
Keep the same products and preserve total cost/macros for each pantry item.
Only convert quantity/unit to a more useful cooking measurement chosen from the Unit enum.
Prefer eggs and other discrete produce as PIECE, garlic as CLOVE, herbs as BUNCH,
dry goods like rice/oats/flour as CUP when a package amount can be reasonably inferred,
and condiments/liquids like soy sauce or oil as CUP/TBSP/TSP when practical.
If package size cannot be inferred with confidence, keep the original quantity/unit.
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

"""Parse a receipt image into pantry ingredients.
The input is a data URL string (e.g. data:image/jpeg;base64,...).
Keep exact product naming from the receipt (brand + product), e.g. "Great Value Chicken Breast".
Return one ingredient per visible food line only. Do NOT invent items that are not present.
Prefer exact label text from line item, including brand/store product prefixes.
Use line-item price as Ingredient.cost and set quantity from visible multipliers/counts; default quantity=1 when unknown.
Skip non-food lines and keep units inside the supported Unit enum.
Prefer recipe-friendly kitchen units when the package size is visible or strongly inferable
(examples: eggs as PIECE, garlic as CLOVE, herbs as BUNCH, rice as CUP, soy sauce as CUP/TBSP/TSP).
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
Correct obvious OCR character/substitution errors in names when confidence is high from nearby tokens
(examples: 7->T in "BU7TR", 0->O in words, dropped vowels in common food words).
Translate receipt shorthand into fully spelled pantry names while keeping visible brand prefixes
(examples: "GV PNT BUTTR" -> "Great Value Peanut Butter", "GV CHNK CHKN" -> "Great Value Chunk Chicken").
If both an abbreviated and a clearer line for the same UPC/item exist, use the clearer fully spelled version.
Keep output names human-readable and standardized for pantry use, not raw receipt code strings.
Prefer recipe-friendly kitchen units when the amount is visible or strongly inferable
(examples: eggs as PIECE, garlic as CLOVE, herbs as BUNCH, rice as CUP, soy sauce as CUP/TBSP/TSP).
Ignore totals/subtotals/tax/payment lines as ingredients.
If OCR text is empty or unreadable, return empty food_line_items, receipt_total=0, and explain in notes.
"""
def parse_receipt_text_into_pantry_items(receipt_text: str) -> ReceiptPantryParse by llm();

def unit_from_any(raw_unit: any) -> Unit {
    unit_text = str(raw_unit).upper();
    if unit_text == "LB" {
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
        fat=float(row.get("fat", 0.0))
    );
}

def ingredient_to_payload(ing: Ingredient) -> dict {
    return {
        "name": ing.name,
        "quantity": ing.quantity,
        "unit": str(ing.unit).split(".")[-1].upper(),
        "cost": ing.cost,
        "protein": ing.protein,
        "carb": ing.carb,
        "fat": ing.fat
    };
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

def _unit_text(raw_unit: any) -> str {
    return str(raw_unit).split(".")[-1].upper().strip();
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

def _history_rating(entry: any) -> float {
    try {
        return float(entry.rating);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_recipe_id(entry: any) -> str {
    try {
        return str(entry.recipe_id).strip();
    } except Exception as _e {
        return "";
    }
}

def _history_title(entry: any) -> str {
    try {
        title = str(entry.title).strip();
        if title != "" {
            return title;
        }
    } except Exception as _e {
        0;
    }
    try {
        return str(entry.name).strip();
    } except Exception as _e {
        return "";
    }
}

def _history_total_calories(entry: any) -> float {
    try {
        return float(entry.total_calories);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_protein_g(entry: any) -> float {
    try {
        return float(entry.total_protein_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_carbs_g(entry: any) -> float {
    try {
        return float(entry.total_carbs_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_total_fat_g(entry: any) -> float {
    try {
        return float(entry.total_fat_g);
    } except Exception as _e {
        return 0.0;
    }
}

def _history_generated_at_ms(entry: any) -> int {
    try {
        return int(entry.generated_at_ms);
    } except Exception as _e {
        return 0;
    }
}

def _history_rating_tier(entry: any) -> str {
    try {
        return str(entry.rating_tier).strip().lower();
    } except Exception as _e {
        return "";
    }
}

def _history_rating_order(entry: any) -> int {
    try {
        return int(entry.rating_order);
    } except Exception as _e {
        return -1;
    }
}

def _history_favorite(entry: any) -> bool {
    try {
        return entry.favorite;
    } except Exception as _e {
        return False;
    }
}

def _history_made(entry: any) -> bool {
    try {
        return entry.made;
    } except Exception as _e {
        return False;
    }
}

def _history_made_at_ms(entry: any) -> int {
    try {
        return int(entry.made_at_ms);
    } except Exception as _e {
        return 0;
    }
}

def _history_notes(entry: any) -> str {
    try {
        return str(entry.notes);
    } except Exception as _e {
        return "Generated from your profile + pantry";
    }
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

def _canonicalize_storage_items(items: list[Ingredient]) -> dict {
    if items == [] {
        return {"items": items, "notes": "", "used_llm": False};
    }
    try {
        normalized = canonicalize_pantry_items_for_storage(items);
        if normalized.items != [] {
            return {
                "items": normalized.items,
                "notes": str(normalized.notes).strip(),
                "used_llm": True
            };
        }
    } except Exception as e {
        return {
            "items": items,
            "notes": "Pantry unit normalization skipped: {}".format(str(e)),
            "used_llm": False
        };
    }
    return {"items": items, "notes": "", "used_llm": False};
}

def _fallback_usage_plan(
    pantry_items: list[IndexedPantryIngredient],
    recipe_ingredients: list[Ingredient]
) -> PantryUsagePlan {
    uses: list[PantryUsage] = [];
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

        for pantry_ing in pantry_items {
            pantry_name = _norm_food_name(pantry_ing.name);
            pantry_unit = _unit_text(pantry_ing.unit);
            if pantry_name != recipe_name or pantry_unit != recipe_unit {
                continue;
            }
            available = pantry_ing.quantity;
            if available <= 0.0 {
                continue;
            }
            used_qty = remaining_qty;
            if used_qty > available {
                used_qty = available;
            }
            if used_qty > 0.0 {
                uses.append(
                    PantryUsage(
                        pantry_index=pantry_ing.pantry_index,
                        quantity_used=used_qty,
                        reason="Exact fallback match"
                    )
                );
                remaining_qty = remaining_qty - used_qty;
            }
            if remaining_qty <= 0.0 {
                break;
            }
        }
        recipe_idx += 1;
    }
    return PantryUsagePlan(
        uses=uses,
        notes="Used exact-match pantry subtraction fallback."
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
            "cost": _round_two(float(row.get("cost", 0.0)) * keep_ratio),
            "protein": _round_two(float(row.get("protein", 0.0)) * keep_ratio),
            "carb": _round_two(float(row.get("carb", 0.0)) * keep_ratio),
            "fat": _round_two(float(row.get("fat", 0.0)) * keep_ratio)
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

            here ++> Recipe(
                recipe_id=recipe_id,
                name=plan.recipe_name,
                instructions=plan.instructions,
                total_calories=plan.total_calories,
                total_protein_g=plan.total_protein_g,
                total_carbs_g=plan.total_carbs_g,
                total_fat_g=plan.total_fat_g,
                generated_at_ms=generated_at_ms
            );

            here ++> RecipeHistoryEntry(
                recipe_id=recipe_id,
                title=plan.recipe_name,
                total_calories=plan.total_calories,
                total_protein_g=plan.total_protein_g,
                total_carbs_g=plan.total_carbs_g,
                total_fat_g=plan.total_fat_g,
                generated_at_ms=generated_at_ms
            );

            result: list = [];
            for ing in plan.recipe_ingredients {
                ing_data = {
                    "name": ing.name,
                    "quantity": ing.quantity,
                    "unit": str(ing.unit).split(".")[-1].lower(),
                    "cost": ing.cost,
                    "protein": ing.protein,
                    "carb": ing.carb,
                    "fat": ing.fat
                };
                here ++> MealIngredient(
                    name=ing_data["name"],
                    quantity=ing_data["quantity"],
                    unit=ing_data["unit"],
                    cost=ing_data["cost"],
                    protein=ing_data["protein"],
                    carb=ing_data["carb"],
                    fat=ing_data["fat"],
                    recipe_id=recipe_id
                );
                result.append(ing_data);
            }

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
    has ingredients: list = [];
    has found_recipe: bool = False;

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with Recipe entry {
        self.found_recipe = True;
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
        self.ingredients.append({
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
        self.recipe["ingredients"] = self.ingredients;
        report self.recipe;
    }
}

walker ListRecipeHistory {
    has recipes: list = [];

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with RecipeHistoryEntry entry {
        self.recipes.append({
            "recipe_id": _history_recipe_id(here),
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
            "notes": _history_notes(here)
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
        if _history_recipe_id(here) != self.recipe_id {
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
    has current_generated_at_ms: int = 0;
    has found_current_recipe: bool = False;

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
        self.current_generated_at_ms = here.generated_at_ms;
    }

    can mark_recipe with RecipeHistoryEntry entry {
        if _history_recipe_id(here) != self.recipe_id {
            return;
        }
        self.updated = True;
        here.made = self.made;
        if self.made {
            here.made_at_ms = self.made_at_ms;
        } else {
            here.made_at_ms = 0;
        }
    }

    can finish with Root exit {
        if not self.updated and self.found_current_recipe {
            here ++> RecipeHistoryEntry(
                recipe_id=self.recipe_id,
                title=self.current_title,
                total_calories=self.current_total_calories,
                total_protein_g=self.current_total_protein_g,
                total_carbs_g=self.current_total_carbs_g,
                total_fat_g=self.current_total_fat_g,
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
        report {
            "updated": True,
            "recipe_id": self.recipe_id,
            "made": self.made,
            "made_at_ms": (self.made_at_ms if self.made else 0)
        };
    }
}

walker SaveRecipeRankingBatch {
    has updates: list[dict];
    has update_map: dict = {};
    has expected_count: int = 0;
    has updated_count: int = 0;

    can collect with Root entry {
        for row in self.updates {
            recipe_id = str(row.get("recipe_id", "")).strip();
            if recipe_id == "" {
                continue;
            }
            if self.update_map.get(recipe_id, None) == None {
                self.expected_count += 1;
            }
            self.update_map[recipe_id] = row;
        }
        if self.expected_count == 0 {
            return;
        }
        visit [-->];
    }

    can apply_update with RecipeHistoryEntry entry {
        recipe_id = _history_recipe_id(here);
        if recipe_id == "" {
            return;
        }
        row = self.update_map.get(recipe_id, None);
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
    }

    can finish with Root exit {
        if self.expected_count == 0 {
            report {"updated": False, "error": "No ranking updates provided", "updated_count": 0};
            return;
        }
        report {
            "updated": self.updated_count == self.expected_count,
            "updated_count": self.updated_count,
            "expected_count": self.expected_count
        };
    }
}

walker DeleteSavedRecipe {
    has recipe_id: str;
    has deleted_history: bool = False;
    has deleted_current_recipe: bool = False;

    can collect with Root entry {
        visit [-->];
    }

    can delete_history with RecipeHistoryEntry entry {
        if _history_recipe_id(here) == self.recipe_id {
            self.deleted_history = True;
            del here;
        }
    }

    can delete_current_recipe with Recipe entry {
        if here.recipe_id == self.recipe_id {
            self.deleted_current_recipe = True;
            del here;
        }
    }

    can delete_current_ingredients with MealIngredient entry {
        if here.recipe_id == self.recipe_id {
            del here;
        }
    }

    can finish with Root exit {
        if not self.deleted_history and not self.deleted_current_recipe {
            report {"deleted": False, "error": "Recipe not found"};
            return;
        }
        report {
            "deleted": True,
            "deleted_current_recipe": self.deleted_current_recipe
        };
    }
}

# Clear persisted recipe state.
walker ClearGeneratedRecipe {
    can collect with Root entry {
        visit [-->];
    }

    can clear_recipe with Recipe entry {
        del here;
    }

    can clear_ingredients with MealIngredient entry {
        del here;
    }

    can done with Root exit {
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

            usage_plan = PantryUsagePlan(uses=[], notes="");
            used_llm = False;
            notes = "";
            try {
                usage_plan = plan_recipe_pantry_subtraction(indexed_pantry, recipe_typed);
                used_llm = True;
                notes = str(usage_plan.notes).strip();
            } except Exception as llm_e {
                usage_plan = _fallback_usage_plan(indexed_pantry, recipe_typed);
                notes = "LLM pantry subtraction failed: {}".format(str(llm_e));
            }

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
                merged_notes = _note_merge(parsed.notes, canonical_notes);
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
                "notes": _note_merge(parsed.notes, canonical_notes)
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
                merged_notes = _note_merge(parsed.notes, canonical_notes);
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
                "notes": _note_merge(parsed.notes, canonical_notes)
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
