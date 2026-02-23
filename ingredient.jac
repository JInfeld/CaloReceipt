"""Ingredient module wiring.
Generate a recipe from a user profile and available pantry ingredients.
"""

import from llm_config {
    llm
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
If a line is uncertain or unreadable, exclude it rather than guessing.
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

# Persisted recipe summary node.
node Recipe {
    has name: str,
        instructions: list[str],
        total_calories: float,
        total_protein_g: float,
        total_carbs_g: float,
        total_fat_g: float;
}

# Persisted ingredient rows for the latest generated recipe.
node MealIngredient {
    has name: str,
        quantity: float,
        unit: str,
        cost: float,
        protein: float,
        carb: float,
        fat: float;
}

# Main recipe generation workflow:
# 1) clear old recipe state
# 2) generate new recipe with LLM
# 3) persist recipe + ingredients
# 4) return response payload for frontend rendering
walker:pub GenerateRecipeFromPantry {
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

            here ++> Recipe(
                name=plan.recipe_name,
                instructions=plan.instructions,
                total_calories=plan.total_calories,
                total_protein_g=plan.total_protein_g,
                total_carbs_g=plan.total_carbs_g,
                total_fat_g=plan.total_fat_g
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
                    fat=ing_data["fat"]
                );
                result.append(ing_data);
            }

            report {
                "ok": True,
                "recipe_name": plan.recipe_name,
                "instructions": plan.instructions,
                "ingredients": result,
                "total_calories": plan.total_calories,
                "total_protein_g": plan.total_protein_g,
                "total_carbs_g": plan.total_carbs_g,
                "total_fat_g": plan.total_fat_g
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
walker:pub ListGeneratedRecipe {
    has recipe: dict = {};
    has ingredients: list = [];

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with Recipe entry {
        self.recipe = {
            "recipe_name": here.name,
            "instructions": here.instructions,
            "total_calories": here.total_calories,
            "total_protein_g": here.total_protein_g,
            "total_carbs_g": here.total_carbs_g,
            "total_fat_g": here.total_fat_g
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
        self.recipe["ingredients"] = self.ingredients;
        report self.recipe;
    }
}

# Clear persisted recipe state.
walker:pub ClearGeneratedRecipe {
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

# Convert receipt image directly into pantry ingredients with a single LLM call.
walker:pub ParseReceiptImageToPantry {
    has image_base64: str;
    has image_mime_type: str = "image/jpeg";

    can run with Root entry {
        try {
            data_url = "data:{};base64,{}".format(self.image_mime_type, self.image_base64);
            parsed = parse_receipt_image_into_pantry_items(data_url);
            items: list = [];
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
                items.append({
                    "name": ing.name,
                    "quantity": ing.quantity,
                    "unit": str(ing.unit).split(".")[-1].upper(),
                    "cost": ing.cost,
                    "protein": ing.protein,
                    "carb": ing.carb,
                    "fat": ing.fat
                });
                parsed_items_total += ing.cost;
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
                merged_notes = parsed.notes;
                if str(merged_notes).strip() == "" {
                    merged_notes = mismatch_note;
                } else {
                    merged_notes = "{} | {}".format(merged_notes, mismatch_note);
                }

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
                "notes": parsed.notes
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

# Convert OCR text into pantry ingredients with a single LLM call.
walker:pub ParseReceiptTextToPantry {
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
            items: list = [];
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
                items.append({
                    "name": ing.name,
                    "quantity": ing.quantity,
                    "unit": str(ing.unit).split(".")[-1].upper(),
                    "cost": ing.cost,
                    "protein": ing.protein,
                    "carb": ing.carb,
                    "fat": ing.fat
                });
                parsed_items_total += ing.cost;
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
                merged_notes = parsed.notes;
                if str(merged_notes).strip() == "" {
                    merged_notes = mismatch_note;
                } else {
                    merged_notes = "{} | {}".format(merged_notes, mismatch_note);
                }

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
                "notes": parsed.notes
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
